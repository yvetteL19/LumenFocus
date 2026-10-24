import Foundation
import Combine

enum AppPhase: Equatable {
    case stopped
    case working
    case triggeringRest
    case resting
    case paused(until: PauseEndTime)
    case autoSuspended(reason: AutoSuspendReason)
}

enum PauseEndTime: Equatable {
    case duration(Date)
    case endOfDay
}

/// UI projection of CycleEngine and StatisticsManager. It owns no timers or storage.
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var currentPhase: AppPhase = .stopped
    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var progress: Double = 1
    @Published private(set) var nextReminderDate: Date?
    @Published private(set) var environmentDetail: String?
    @Published private(set) var todayRestCount: Int = 0
    @Published private(set) var todayWorkDuration: Int = 0
    /// A small, session-only receipt for the last break. Never a health claim or persistent score.
    @Published private(set) var lastRestOutcome: RestEndReason?

    init() {}

    func clearRestOutcome() {
        if lastRestOutcome != nil { lastRestOutcome = nil }
    }

    func recordRestOutcome(_ reason: RestEndReason) {
        guard currentPhase == .working, reason != .interrupted else {
            clearRestOutcome()
            return
        }
        if lastRestOutcome != reason { lastRestOutcome = reason }
    }

    var isPaused: Bool {
        if case .paused = currentPhase { return true }
        return false
    }

    var isAutoSuspended: Bool {
        if case .autoSuspended = currentPhase { return true }
        return false
    }

    var isSuspended: Bool { isPaused || isAutoSuspended }
    var isWorking: Bool { currentPhase == .working }
    var isResting: Bool { currentPhase == .resting || currentPhase == .triggeringRest }

    var formattedRemainingTime: String {
        String(format: "%d:%02d", max(0, remainingSeconds) / 60, max(0, remainingSeconds) % 60)
    }

    var formattedTodayWorkDuration: String { formatWorkDuration(todayWorkDuration) }

    func apply(_ snapshot: CycleSnapshot) {
        let phase: AppPhase
        switch snapshot.phase {
        case .stopped:
            phase = .stopped
        case .working:
            phase = .working
        case .resting:
            if let rest = snapshot.rest, rest.elapsed < rest.fadeInDuration {
                phase = .triggeringRest
            } else {
                phase = .resting
            }
        case .paused:
            phase = .paused(until: .duration(snapshot.pauseUntil ?? Date()))
        case .suspended:
            phase = .autoSuspended(reason: snapshot.environment.reason ?? .screenLocked)
        }
        let seconds = Int(ceil(max(0, snapshot.remaining)))
        if remainingSeconds != seconds { remainingSeconds = seconds }
        if progress != snapshot.progress { progress = snapshot.progress }
        if nextReminderDate != snapshot.nextReminderDate { nextReminderDate = snapshot.nextReminderDate }
        let detail: String?
        if snapshot.environment.isAway {
            detail = L("屏幕已锁定或睡眠，提醒和工作计时已暂停。")
        } else {
            detail = nil
        }
        if environmentDetail != detail { environmentDetail = detail }
        if currentPhase != phase { currentPhase = phase }
        if phase != .working { clearRestOutcome() }
    }

    func refreshStatistics() {
        let today = StatisticsManager.shared.refreshToday()
        if todayRestCount != today.restCount { todayRestCount = today.restCount }
        if todayWorkDuration != today.workDuration { todayWorkDuration = today.workDuration }
    }

    /// Kept for AppDelegate's termination hook; never mirrors legacy UserDefaults keys.
    func saveTodayStatistics() {
        StatisticsManager.shared.flush()
        refreshStatistics()
    }

    // Existing action call sites delegate to the engine instead of mutating this projection.
    func pause(duration: TimeInterval? = nil) { TimerManager.shared.pause(duration: duration) }
    func resume() { TimerManager.shared.resume() }
    func cancelRest() { TimerManager.shared.cancelCurrentRest() }
}
