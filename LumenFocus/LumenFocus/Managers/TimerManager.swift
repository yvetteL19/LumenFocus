import Foundation
import Combine

/// Connects the pure cycle engine to preferences, physical lifecycle and records.
/// The timer is only a heartbeat; CycleEngine owns elapsed time and deadlines.
final class TimerManager: ObservableObject {
    static let shared = TimerManager()

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lifecycleStarted = false
    private var shortcutPolicy = RestShortcutPolicy()
    private let shortcutClock = SystemCycleClock()
    private let appState = AppState.shared
    private let restController = RestController.shared
    private let workspaceMonitor = WorkspaceMonitor.shared
    private let engine: CycleEngine

    var isRunning: Bool { timer?.isValid == true }

    private init() {
        engine = CycleEngine(configuration: Self.configuration())
        engine.setEnvironment(workspaceMonitor.environment.value)
        setupSubscriptions()
        synchronize()
    }

    /// Process startup restores the user's enabled/pause preferences. It does not enable reminders.
    func start() {
        guard !lifecycleStarted else { return }
        lifecycleStarted = true
        appState.clearRestOutcome()
        refreshConfiguration()
        applyReminderPreferences()
    }

    /// Process shutdown flushes elapsed work but preserves the user's next-launch choice.
    func stop() {
        lifecycleStarted = false
        appState.clearRestOutcome()
        invalidateHeartbeat()
        engine.stop()
        synchronize()
        StatisticsManager.shared.flush()
    }

    func startReminders() {
        let settings = AppSettings.shared
        settings.remindersEnabled = true
        settings.remindersPausedUntil = nil
        lifecycleStarted = true
        appState.clearRestOutcome()
        refreshConfiguration()
        engine.start()
        scheduleHeartbeat()
        synchronize()
    }

    func stopReminders() {
        AppSettings.shared.remindersEnabled = false
        AppSettings.shared.remindersPausedUntil = nil
        appState.clearRestOutcome()
        invalidateHeartbeat()
        engine.stop()
        synchronize()
        StatisticsManager.shared.flush()
    }

    /// Pausing suppresses reminders while work measurement continues.
    func pause(duration: TimeInterval? = nil) {
        guard AppSettings.shared.remindersEnabled, engine.isStarted else { return }
        let now = Date()
        let until: Date
        if let duration {
            guard duration.isFinite, duration > 0 else { return }
            until = now.addingTimeInterval(duration)
        } else {
            until = Calendar.current.date(byAdding: .day, value: 1,
                                          to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(86400)
        }
        guard until.timeIntervalSinceReferenceDate.isFinite else { return }
        appState.clearRestOutcome()
        AppSettings.shared.remindersPausedUntil = until
        engine.pause(until: until)
        synchronize()
        StatisticsManager.shared.flush()
    }

    func resume() {
        guard AppSettings.shared.remindersEnabled, engine.isStarted else { return }
        appState.clearRestOutcome()
        AppSettings.shared.remindersPausedUntil = nil
        engine.resume()
        scheduleHeartbeat()
        synchronize()
    }

    func toggleRestViaShortcut() {
        switch shortcutPolicy.pressed(isResting: engine.snapshot.rest != nil, at: shortcutClock.elapsed) {
        case .cancel: cancelCurrentRest()
        case .start: triggerManualRest()
        case .ignore: break
        }
    }

    func restShortcutReleased() { shortcutPolicy.released() }

    func triggerManualRest() {
        // A manual action must never silently enable reminders or end a pause.
        guard AppSettings.shared.remindersEnabled, engine.isStarted,
              engine.snapshot.pauseUntil == nil, AppSettings.shared.remindersPausedUntil == nil,
              !engine.snapshot.environment.isAway else { return }
        appState.clearRestOutcome()
        engine.beginRest(using: Self.configuration())
        synchronize()
        StatisticsManager.shared.flush()
    }

    func skipReminder() {
        guard AppSettings.shared.remindersEnabled, AppSettings.shared.remindersPausedUntil == nil,
              engine.isStarted, engine.snapshot.pauseUntil == nil else { return }
        appState.clearRestOutcome()
        engine.skipReminder()
        synchronize()
        StatisticsManager.shared.flush()
    }

    func cancelCurrentRest() {
        engine.cancelRest()
        synchronize()
        StatisticsManager.shared.flush()
    }

    @available(*, deprecated, renamed: "triggerManualRest")
    func triggerTestRest() { triggerManualRest() }

    @available(*, deprecated, renamed: "cancelCurrentRest")
    func cancelRest() { cancelCurrentRest() }

    private static func configuration() -> CycleEngine.Configuration {
        let settings = AppSettings.shared
        return CycleEngine.Configuration(workDuration: TimeInterval(settings.workDurationMinutes * 60),
                                         restDuration: TimeInterval(settings.restDurationSeconds),
                                         fadeInDuration: RestController.fadeInDuration,
                                         fadeOutDuration: RestController.fadeOutDuration)
    }

    private func refreshConfiguration() {
        let latest = Self.configuration()
        if engine.configuration != latest { engine.configure(latest) }
    }

    private func applyReminderPreferences() {
        guard lifecycleStarted else { return }
        let settings = AppSettings.shared
        if !settings.remindersEnabled {
            if settings.remindersPausedUntil != nil { settings.remindersPausedUntil = nil }
            invalidateHeartbeat()
            engine.stop()
        } else {
            let pause = settings.remindersPausedUntil.flatMap { date in
                date.timeIntervalSinceReferenceDate.isFinite && date > Date() ? date : nil
            }
            if settings.remindersPausedUntil != pause { settings.remindersPausedUntil = pause }
            if !engine.isStarted {
                engine.start(pausedUntil: pause)
            } else if engine.snapshot.pauseUntil != pause {
                if let pause { engine.pause(until: pause) }
                else { engine.resume() }
            }
            scheduleHeartbeat()
        }
        synchronize()
        StatisticsManager.shared.flush()
    }

    private func setupSubscriptions() {
        // Handle sleep synchronously before the main run loop is suspended.
        workspaceMonitor.environment
            .sink { [weak self] value in
                guard let self else { return }
                self.engine.setEnvironment(value)
                self.synchronize()
                if value.isAway { StatisticsManager.shared.flush() }
            }
            .store(in: &cancellables)

        let settings = AppSettings.shared
        Publishers.Merge(settings.$workDurationMinutes.map { _ in () },
                         settings.$restDurationSeconds.map { _ in () })
            .dropFirst(2)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.appState.clearRestOutcome()
                self.engine.configure(Self.configuration())
                self.synchronize()
            }
            .store(in: &cancellables)

        settings.$remindersEnabled.combineLatest(settings.$remindersPausedUntil)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyReminderPreferences() }
            .store(in: &cancellables)
    }

    private func invalidateHeartbeat() {
        timer?.invalidate()
        timer = nil
    }

    private func scheduleHeartbeat() {
        guard timer == nil else { return }
        let value = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.engine.tick()
            self.synchronize()
        }
        RunLoop.main.add(value, forMode: .common)
        timer = value
    }

    private func synchronize() {
        let events = engine.drainEvents()
        let statistics = StatisticsManager.shared
        for event in events {
            switch event {
            case .workRecorded(let from, let to): statistics.recordWork(from: from, to: to)
            case .restEnded(let id, let date, .completed): statistics.recordCompletedRest(at: date, id: id)
            case .pauseExpired(let until):
                // Expiry can be observed by wake/configure as well as heartbeat.
                // Never clear a newer pause written before an older event was drained.
                if AppSettings.shared.remindersPausedUntil == until { AppSettings.shared.remindersPausedUntil = nil }
            case .restEnded, .naturalBreak: break
            }
        }
        let snapshot = engine.snapshot
        appState.apply(snapshot)
        appState.refreshStatistics()
        restController.render(snapshot.rest)
        for case .restEnded(_, _, let reason) in events {
            shortcutPolicy.restDidEnd(at: shortcutClock.elapsed)
            appState.recordRestOutcome(reason)
            restController.publishEnd(reason)
            statistics.flush()
        }
    }
}
