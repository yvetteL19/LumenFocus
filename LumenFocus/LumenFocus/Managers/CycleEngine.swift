import Foundation

/// Calendar time is used for labels/records; elapsed time is used for deadlines.
/// The production elapsed clock advances through sleep and is unaffected by clock edits.
protocol CycleClock {
    var now: Date { get }
    var elapsed: TimeInterval { get }
}

final class SystemCycleClock: CycleClock {
    private let origin = ContinuousClock.now
    var now: Date { Date() }
    var elapsed: TimeInterval {
        let value = origin.duration(to: .now).components
        return Double(value.seconds) + Double(value.attoseconds) / 1_000_000_000_000_000_000
    }
}

enum AutoSuspendReason: Equatable {
    case screenLocked
}

/// Only physical lock/sleep suspends reminders and establishes away time.
struct CycleEnvironment: Equatable {
    var reason: AutoSuspendReason?
    var detail: String?
    var isAway: Bool

    static let available = CycleEnvironment(reason: nil, detail: nil, isAway: false)
    var suppressesReminder: Bool { isAway }
}

enum RestEndReason: Equatable {
    case completed
    case userCancelled
    case interrupted
}

enum CyclePhase: Equatable {
    case stopped, working, resting, paused, suspended
}

struct CycleRestProgress: Equatable {
    let id: UUID
    let duration: TimeInterval
    let elapsed: TimeInterval
    let fadeInDuration: TimeInterval
    let fadeOutDuration: TimeInterval

    var remaining: TimeInterval {
        max(0, duration - max(0, elapsed - fadeInDuration))
    }
}

struct CycleSnapshot: Equatable {
    let phase: CyclePhase
    let remaining: TimeInterval
    let progress: Double
    let nextReminderDate: Date?
    let pauseUntil: Date?
    let environment: CycleEnvironment
    let rest: CycleRestProgress?
}

enum CycleEvent: Equatable {
    case workRecorded(from: Date, to: Date)
    case restEnded(id: UUID, at: Date, reason: RestEndReason)
    case naturalBreak(duration: TimeInterval)
    case pauseExpired(until: Date)
}

/// The only owner of cycle deadlines and transitions. No timers, windows, or persistence.
/// A heartbeat merely asks this engine to observe the clock; it never decrements counters.
final class CycleEngine {
    struct Configuration: Equatable {
        var workDuration: TimeInterval
        var restDuration: TimeInterval
        var recoveryGrace: TimeInterval = 60
        var fadeInDuration: TimeInterval = 2
        var fadeOutDuration: TimeInterval = 1
    }

    private struct Reading {
        let date: Date
        let elapsed: TimeInterval
    }

    private struct RestSession {
        let id: UUID
        let started: TimeInterval
        let duration: TimeInterval
        let fadeIn: TimeInterval
        let fadeOut: TimeInterval
        var ends: TimeInterval { started + fadeIn + duration + fadeOut }
    }

    private let clock: CycleClock
    private(set) var configuration: Configuration
    private(set) var isStarted = false
    private(set) var environment = CycleEnvironment.available
    private var lastReading: Reading
    private var workDeadline: TimeInterval
    private var graceDeadline: TimeInterval?
    private var manualPauseDeadline: TimeInterval?
    private var manualPauseDate: Date?
    private var awayStarted: TimeInterval?
    private var restSession: RestSession?
    private var events: [CycleEvent] = []

    init(clock: CycleClock = SystemCycleClock(), configuration: Configuration) {
        self.clock = clock
        self.configuration = Self.validated(configuration)
        let reading = Reading(date: clock.now, elapsed: clock.elapsed)
        lastReading = reading
        workDeadline = reading.elapsed + self.configuration.workDuration
    }

    var snapshot: CycleSnapshot {
        let now = lastReading
        let effectiveDeadline = max(workDeadline, graceDeadline ?? workDeadline)
        let rest = restSession.map {
            CycleRestProgress(id: $0.id, duration: $0.duration,
                              elapsed: max(0, now.elapsed - $0.started),
                              fadeInDuration: $0.fadeIn, fadeOutDuration: $0.fadeOut)
        }
        let phase: CyclePhase
        if !isStarted { phase = .stopped }
        else if rest != nil { phase = .resting }
        else if manualPauseDeadline != nil { phase = .paused }
        else if environment.suppressesReminder { phase = .suspended }
        else { phase = .working }

        let remaining = rest?.remaining ?? max(0, effectiveDeadline - now.elapsed)
        let duration = rest?.duration ?? configuration.workDuration
        let nextDate: Date? = phase == .working
            ? now.date.addingTimeInterval(max(0, effectiveDeadline - now.elapsed)) : nil
        return CycleSnapshot(phase: phase, remaining: remaining,
                             progress: min(1, max(0, remaining / duration)),
                             nextReminderDate: nextDate, pauseUntil: manualPauseDate,
                             environment: environment, rest: rest)
    }

    func drainEvents() -> [CycleEvent] {
        let result = events
        events.removeAll(keepingCapacity: true)
        return result
    }

    func start(pausedUntil: Date? = nil) {
        observe(allowAutomaticRest: false)
        endRest(reason: .interrupted)
        isStarted = true
        manualPauseDeadline = nil
        manualPauseDate = nil
        graceDeadline = nil
        awayStarted = environment.isAway ? lastReading.elapsed : nil
        startNextWorkPeriod()
        if let pausedUntil, pausedUntil.timeIntervalSinceReferenceDate.isFinite, pausedUntil > lastReading.date {
            manualPauseDate = pausedUntil
            manualPauseDeadline = lastReading.elapsed + pausedUntil.timeIntervalSince(lastReading.date)
        }
    }

    func stop() {
        observe(allowAutomaticRest: false)
        endRest(reason: .interrupted)
        isStarted = false
        manualPauseDeadline = nil
        manualPauseDate = nil
    }

    func tick() { observe() }

    func configure(_ value: Configuration) {
        observe(allowAutomaticRest: false)
        let value = Self.validated(value)
        // Preserve time already worked when the user changes the interval.
        if restSession == nil {
            workDeadline += value.workDuration - configuration.workDuration
        }
        configuration = value
        // An existing rest keeps its own duration and transitions until it ends.
    }

    func pause(until date: Date) {
        guard isStarted, date.timeIntervalSinceReferenceDate.isFinite else { return }
        observe(allowAutomaticRest: false)
        endRest(reason: .interrupted)
        let delay = max(0, date.timeIntervalSince(lastReading.date))
        manualPauseDeadline = lastReading.elapsed + delay
        manualPauseDate = date
        // Replacing a value replaces the pause. There are no pending resume callbacks.
        expirePauseIfNeeded()
    }

    func resume() {
        let wasPaused = manualPauseDeadline != nil
        observe(allowAutomaticRest: false)
        if wasPaused {
            manualPauseDeadline = nil
            manualPauseDate = nil
            startNextWorkPeriod()
        }
        // Physical lock/sleep remains independent of the user's pause.
    }

    func beginRest(using latestConfiguration: Configuration? = nil) {
        // A user action may arrive before an asynchronous preferences observer.
        // Apply its current settings atomically before creating the session.
        if let latestConfiguration { configure(latestConfiguration) }
        observe(allowAutomaticRest: false)
        guard isStarted, !environment.isAway, manualPauseDeadline == nil, restSession == nil else { return }
        graceDeadline = nil
        beginRestAtCurrentTime()
    }

    func cancelRest() {
        observe(allowAutomaticRest: false)
        guard restSession != nil else { return }
        endRest(reason: .userCancelled)
        // Early return is not completion. Give the user the full next interval.
        startNextWorkPeriod()
    }

    func skipReminder() {
        observe(allowAutomaticRest: false)
        endRest(reason: .userCancelled)
        startNextWorkPeriod()
    }

    func setEnvironment(_ value: CycleEnvironment) {
        observe(allowAutomaticRest: false)
        let previous = environment
        environment = value.isAway ? CycleEnvironment(reason: .screenLocked, detail: nil, isAway: true) : .available

        if !previous.isAway && value.isAway {
            awayStarted = lastReading.elapsed
            endRest(reason: .interrupted)
        } else if previous.isAway && !value.isAway {
            let duration = max(0, lastReading.elapsed - (awayStarted ?? lastReading.elapsed))
            awayStarted = nil
            if isStarted && duration >= configuration.restDuration {
                events.append(.naturalBreak(duration: duration))
                startNextWorkPeriod()
            }
            beginRecoveryGrace()
        }
    }

    private func observe(allowAutomaticRest: Bool = true) {
        let reading = Reading(date: clock.now, elapsed: max(lastReading.elapsed, clock.elapsed))
        let previous = lastReading
        lastReading = reading
        guard isStarted else { return }

        var workStarts = previous.elapsed
        if let rest = restSession {
            guard reading.elapsed >= rest.ends else {
                expirePauseIfNeeded()
                return
            }
            restSession = nil
            let completionDate = date(at: rest.ends)
            events.append(.restEnded(id: rest.id, at: completionDate, reason: .completed))
            workDeadline = rest.ends + configuration.workDuration
            workStarts = max(workStarts, rest.ends)
        }
        if !environment.isAway && reading.elapsed > workStarts {
            events.append(.workRecorded(from: date(at: workStarts), to: reading.date))
        }
        expirePauseIfNeeded()
        if allowAutomaticRest && restSession == nil && manualPauseDeadline == nil && !environment.isAway
            && reading.elapsed >= max(workDeadline, graceDeadline ?? workDeadline) {
            beginRestAtCurrentTime()
        }
    }

    private func date(at elapsed: TimeInterval) -> Date {
        lastReading.date.addingTimeInterval(elapsed - lastReading.elapsed)
    }

    private func endRest(reason: RestEndReason) {
        guard let rest = restSession else { return }
        restSession = nil
        events.append(.restEnded(id: rest.id, at: lastReading.date, reason: reason))
    }

    private func beginRestAtCurrentTime() {
        restSession = RestSession(id: UUID(), started: lastReading.elapsed,
                                  duration: configuration.restDuration,
                                  fadeIn: configuration.fadeInDuration,
                                  fadeOut: configuration.fadeOutDuration)
    }

    private func startNextWorkPeriod(at elapsed: TimeInterval? = nil) {
        workDeadline = (elapsed ?? lastReading.elapsed) + configuration.workDuration
        graceDeadline = nil
    }

    private func beginRecoveryGrace() {
        graceDeadline = max(graceDeadline ?? 0, lastReading.elapsed + configuration.recoveryGrace)
    }

    private func expirePauseIfNeeded() {
        guard let deadline = manualPauseDeadline, lastReading.elapsed >= deadline else { return }
        if let date = manualPauseDate { events.append(.pauseExpired(until: date)) }
        manualPauseDeadline = nil
        manualPauseDate = nil
        startNextWorkPeriod(at: deadline)
    }

    private static func validated(_ value: Configuration) -> Configuration {
        var value = value
        value.workDuration = value.workDuration.isFinite ? max(1, value.workDuration) : 40 * 60
        value.restDuration = value.restDuration.isFinite ? max(1, value.restDuration) : 20
        value.recoveryGrace = max(0, value.recoveryGrace)
        value.fadeInDuration = max(0, value.fadeInDuration)
        value.fadeOutDuration = max(0, value.fadeOutDuration)
        return value
    }
}
