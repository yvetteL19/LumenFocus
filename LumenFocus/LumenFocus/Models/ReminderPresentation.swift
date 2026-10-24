import Foundation

/// Display-only decisions shared by the popover and native menu. No timer or settings writes.
struct ReminderPresentation {
    static let pauseChoices = [60, 120, 240]

    enum Action: Equatable {
        case startReminders, startRest, resumeReminders, endRest
    }

    let phase: AppPhase
    let remainingSeconds: Int
    let nextReminderDate: Date?
    let environmentDetail: String?
    let restDurationSeconds: Int
    let lastRestOutcome: RestEndReason?

    init(phase: AppPhase, remainingSeconds: Int, nextReminderDate: Date?, environmentDetail: String?,
         restDurationSeconds: Int = 300, lastRestOutcome: RestEndReason? = nil) {
        self.phase = phase
        self.remainingSeconds = remainingSeconds
        self.nextReminderDate = nextReminderDate
        self.environmentDetail = environmentDetail
        self.restDurationSeconds = restDurationSeconds
        self.lastRestOutcome = lastRestOutcome
    }

    var titleKey: String {
        switch phase {
        case .stopped: return "提醒已停止"
        case .working: return "下次提醒"
        case .triggeringRest: return "休息一下"
        case .resting: return "剩余休息时间"
        case .paused: return "提醒已暂停"
        case .autoSuspended: return "提醒暂缓"
        }
    }

    var symbolName: String {
        switch phase {
        case .stopped: return "stop.circle"
        case .working: return "clock"
        case .triggeringRest, .resting: return "leaf"
        case .paused, .autoSuspended: return "pause.circle"
        }
    }

    var primaryAction: Action {
        switch phase {
        case .stopped: return .startReminders
        case .paused: return .resumeReminders
        case .triggeringRest, .resting: return .endRest
        case .working, .autoSuspended: return .startRest
        }
    }

    var primaryTitleKey: String {
        switch phase {
        case .stopped: return "开启提醒"
        case .paused: return "恢复提醒"
        case .triggeringRest, .resting: return "返回工作"
        case .working, .autoSuspended: return "休息一下"
        }
    }

    func primaryTitle(localize: (String) -> String = { L($0) }) -> String {
        localize(primaryTitleKey)
    }

    var pauseMenuTitleKey: String {
        if case .paused = phase { return "调整暂停时间" }
        return "暂停提醒"
    }

    func value(localize: (String) -> String = { L($0) },
               clockText: (Date) -> String = ReminderPresentation.clockText) -> String {
        switch phase {
        case .stopped: return "—"
        case .working:
            return nextReminderDate.map(clockText) ?? Self.countdown(seconds: remainingSeconds)
        case .triggeringRest, .resting: return Self.countdown(seconds: remainingSeconds)
        case .paused(let until):
            switch until {
            case .duration(let date): return clockText(date)
            case .endOfDay: return localize("至今日结束")
            }
        case .autoSuspended: return localize("暂不打扰")
        }
    }

    func detail(localize: ((String) -> String)? = nil) -> String {
        let translate = localize ?? { L($0) }
        switch phase {
        case .stopped: return translate("开启后，会按设定间隔自动渐暗。")
        case .working: return Self.remainingDescription(seconds: remainingSeconds, localize: localize)
        case .triggeringRest, .resting:
            return translate("休息结束后自动恢复，按任意键可随时返回。")
        case .paused:
            return translate("届时恢复计时，按设定间隔再次渐暗。")
        case .autoSuspended:
            return environmentDetail ?? translate("屏幕已锁定或睡眠，提醒和工作计时已暂停。")
        }
    }

    /// The outcome remains quiet and stable while the next reminder time stays prominent.
    /// It is never shown in a different phase, where it could contradict the current controls.
    func outcomeText(localize: (String) -> String = { L($0) }) -> String? {
        guard phase == .working, let lastRestOutcome else { return nil }
        switch lastRestOutcome {
        case .completed: return localize("休息已完成")
        case .userCancelled: return localize("已返回工作")
        case .interrupted: return nil
        }
    }

    static func skipTitle(workMinutes: Int, now: Date = Date(),
                          localize: (String) -> String = { L($0) },
                          clockText: ((Date) -> String)? = nil) -> String {
        let next = now.addingTimeInterval(TimeInterval(max(0, workMinutes) * 60))
        return String(format: localize("跳过 · 下次 %@"),
                      clockText?(next) ?? Self.clockText(next, relativeTo: now))
    }

    static func menuBarCountdown(seconds: Int) -> String {
        guard seconds > 0 else { return "0m" }
        guard seconds >= 60 else { return "<1m" }
        let minutes = seconds / 60 + (seconds % 60 == 0 ? 0 : 1)
        return "\(minutes)m"
    }

    static func remainingDescription(seconds: Int, localize: ((String) -> String)? = nil) -> String {
        let translate = localize ?? { L($0) }
        guard seconds > 0 else { return translate("即将提醒") }
        let duration = localize.map { durationText(seconds: seconds, localize: $0) } ?? durationText(seconds: seconds)
        return String(format: translate("还有 %@"), duration)
    }

    static func durationText(seconds: Int) -> String { formatBreakDuration(seconds) }

    static func durationText(seconds: Int, localize: (String) -> String) -> String {
        let seconds = max(0, seconds)
        let minutes = seconds / 60
        let remainder = seconds % 60
        if minutes == 0 { return String(format: localize("%d 秒"), remainder) }
        if remainder == 0 { return String(format: localize("%d 分钟"), minutes) }
        return String(format: localize("%d 分 %d 秒"), minutes, remainder)
    }

    static func rhythmSummary(workMinutes: Int, restSeconds: Int,
                              localize: (String) -> String = { L($0) }) -> String {
        let work = String(format: localize("%d 分钟"), max(0, workMinutes))
        let rest = durationText(seconds: restSeconds, localize: localize)
        return String(format: localize("工作 %@ · 休息 %@"), work, rest)
    }

    static func pauseOptionTitle(minutes: Int, now: Date = Date(),
                                 localize: (String) -> String = { L($0) },
                                 durationText: (Int) -> String = { formatBreakDuration($0) },
                                 clockText: ((Date) -> String)? = nil) -> String {
        let until = now.addingTimeInterval(TimeInterval(minutes) * 60)
        return String(format: localize("暂停 %@ · %@"), durationText(minutes * 60),
                      clockText?(until) ?? Self.clockText(until, relativeTo: now))
    }

    static func clockText(_ date: Date) -> String {
        clockText(date, relativeTo: Date())
    }

    static func clockText(_ date: Date, relativeTo now: Date,
                          calendar: Calendar = .current, locale: Locale = AppLocalization.locale,
                          localize: (String) -> String = { L($0) }) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        if calendar.isDate(date, inSameDayAs: now) { return formatter.string(from: date) }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(format: localize("明天 %@"), formatter.string(from: date))
        }
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }

    private static func countdown(seconds: Int) -> String {
        let seconds = max(0, seconds)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
