import Foundation

/// Display-only decisions shared by the popover and native menu. No timer or settings writes.
struct ReminderPresentation {
    enum Action: Equatable {
        case startRest, resumeReminders, endRest
    }

    let phase: AppPhase
    let remainingSeconds: Int
    let nextReminderDate: Date?
    let environmentDetail: String?

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
        case .triggeringRest, .resting: return "结束休息"
        case .working, .autoSuspended: return "现在休息"
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
        case .reminderDue: return localize("该休息一下了")
        case .triggeringRest, .resting: return Self.countdown(seconds: remainingSeconds)
        case .paused(let until):
            switch until {
            case .duration(let date): return clockText(date)
            case .endOfDay: return localize("至今日结束")
            }
        case .autoSuspended: return localize("暂不打扰")
        }
    }

    func detail(localize: (String) -> String = { L($0) }) -> String {
        switch phase {
        case .working:
            let countdown = Self.remainingDescription(seconds: remainingSeconds, localize: localize)
            if let environmentDetail, !environmentDetail.isEmpty {
                return countdown + "\n" + environmentDetail
            }
            return countdown
        case .reminderDue: return localize("准备好再开始，当前工作不会被遮挡。")
        case .triggeringRest, .resting: return localize("看向屏幕之外。你可以随时结束或延后。")
        case .paused(let until):
            switch until {
            case .duration: return localize("届时结束暂停；应用规则仍然生效。工作时长继续累计。")
            case .endOfDay: return localize("明天恢复提醒，也可随时手动恢复。")
            }
        case .autoSuspended:
            if let environmentDetail, !environmentDetail.isEmpty { return environmentDetail }
            return localize("规则解除后会留出缓冲，再恢复提醒。")
        }
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

    static func remainingDescription(seconds: Int, localize: (String) -> String = { L($0) }) -> String {
        guard seconds > 0 else { return localize("即将提醒") }
        return String(format: localize("还有 %@"), durationText(seconds: seconds, localize: localize))
    }

    static func durationText(seconds: Int, localize: (String) -> String = { L($0) }) -> String {
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
                                 clockText: (Date) -> String = ReminderPresentation.clockText) -> String {
        let until = now.addingTimeInterval(TimeInterval(minutes) * 60)
        return String(format: localize("暂停 %d 分钟 · %@"), minutes, clockText(until))
    }

    static func clockText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private static func countdown(seconds: Int) -> String {
        let seconds = max(0, seconds)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
