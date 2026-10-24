import Foundation

/// Display-only decisions shared by the popover and native menu. No timer or settings writes.
struct ReminderPresentation {
    static let defaultSnoozeMinutes = 5
    static let delayChoices = [2, 5, 10]
    static let pauseChoices = [15, 60]
    static var defaultSnoozeSeconds: TimeInterval { TimeInterval(defaultSnoozeMinutes * 60) }

    enum Action: Equatable {
        case startRest, resumeReminders, endRest
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
        case .working: return "下次提醒"
        case .reminderDue: return "休息提醒"
        case .triggeringRest: return "准备离屏休息"
        case .resting: return "剩余休息时间"
        case .paused: return "提醒已暂停"
        case .autoSuspended: return "提醒暂缓"
        }
    }

    var symbolName: String {
        switch phase {
        case .working: return "clock"
        case .reminderDue: return "eye"
        case .triggeringRest, .resting: return "leaf"
        case .paused, .autoSuspended: return "pause.circle"
        }
    }

    var primaryAction: Action {
        switch phase {
        case .paused: return .resumeReminders
        case .triggeringRest, .resting: return .endRest
        case .working, .reminderDue, .autoSuspended: return .startRest
        }
    }

    var primaryTitleKey: String {
        switch phase {
        case .reminderDue: return "开始休息"
        case .paused: return "恢复提醒"
        case .triggeringRest, .resting: return "提前结束"
        case .working, .autoSuspended: return "现在休息"
        }
    }

    func primaryTitle(localize: (String) -> String = { L($0) }) -> String {
        switch phase {
        case .working, .autoSuspended:
            return String(format: localize("现在休息 %@"), formatBreakDuration(restDurationSeconds))
        default:
            return localize(primaryTitleKey)
        }
    }

    var pauseMenuTitleKey: String {
        if case .paused = phase { return "调整暂停时间" }
        return "暂停提醒"
    }

    func value(localize: (String) -> String = { L($0) },
               clockText: (Date) -> String = ReminderPresentation.clockText) -> String {
        switch phase {
        case .working:
            return nextReminderDate.map(clockText) ?? Self.countdown(seconds: remainingSeconds)
        case .reminderDue: return Self.restInvitationTitle(seconds: restDurationSeconds, localize: localize)
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
        case .working:
            let countdown = Self.remainingDescription(seconds: remainingSeconds, localize: localize)
            if let environmentDetail, !environmentDetail.isEmpty {
                return countdown + "\n" + environmentDetail
            }
            return countdown
        case .reminderDue: return translate("开始后，所有屏幕会渐暗。你可以随时提前结束。")
        case .triggeringRest, .resting: return translate("看向屏幕之外。你可以随时结束或延后。")
        case .paused(let until):
            switch until {
            case .duration: return translate("届时结束暂停；应用规则仍然生效。工作时长继续累计。")
            case .endOfDay: return translate("明天恢复提醒，也可随时手动恢复。")
            }
        case .autoSuspended:
            if let environmentDetail, !environmentDetail.isEmpty { return environmentDetail }
            return translate("规则解除后会留出缓冲，再恢复提醒。")
        }
    }

    /// The outcome remains quiet and stable while the next reminder time stays prominent.
    /// It is never shown in a different phase, where it could contradict the current controls.
    func outcomeText(localize: (String) -> String = { L($0) }) -> String? {
        guard phase == .working, let lastRestOutcome else { return nil }
        switch lastRestOutcome {
        case .completed: return localize("休息已完成")
        case .userCancelled: return localize("已提前结束，未计入完成次数。")
        case .snoozed: return localize("已延后提醒")
        case .interrupted: return nil
        }
    }

    static func restInvitationTitle(seconds: Int, localize: (String) -> String = { L($0) }) -> String {
        String(format: localize("离屏休息 %@"), formatBreakDuration(seconds))
    }

    static func defaultSnoozeTitle(localize: (String) -> String = { L($0) }) -> String {
        String(format: localize("%@后再提醒"), formatBreakDuration(defaultSnoozeMinutes * 60))
    }

    static func skipTitle(workMinutes: Int, now: Date = Date(),
                          localize: (String) -> String = { L($0) },
                          clockText: ((Date) -> String)? = nil) -> String {
        let next = now.addingTimeInterval(TimeInterval(max(0, workMinutes) * 60))
        return String(format: localize("跳过 · 下次 %@"),
                      clockText?(next) ?? Self.clockText(next, relativeTo: now))
    }

    func delayOptionTitle(minutes: Int, now: Date = Date(),
                          localize: (String) -> String = { L($0) }) -> String {
        String(format: localize("延后 %@ · %@"), formatBreakDuration(minutes * 60),
               Self.clockText(delayedReminderDate(minutes: minutes, now: now), relativeTo: now))
    }

    func delayedReminderDate(minutes: Int, now: Date = Date()) -> Date {
        let base: Date
        if case .working = phase {
            base = max(nextReminderDate ?? now, now)
        } else {
            base = now
        }
        return base.addingTimeInterval(TimeInterval(minutes) * 60)
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
