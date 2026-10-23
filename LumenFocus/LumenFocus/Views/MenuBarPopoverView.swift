import SwiftUI

/// The next reminder and the user's controls are the primary menu-bar experience.
struct MenuBarPopoverView: View {
    @ObservedObject private var appState = AppState.shared
    var onClose: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: statusTitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(verbatim: statusValue)
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Text(verbatim: statusDetail)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            phaseControls
            Divider()
            Text(verbatim: String(format: L("今日完成 %d 次休息 · 已计时 %@"), appState.todayRestCount, appState.formattedTodayWorkDuration))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            HStack {
                Button("详细统计") { onClose(); StatisticsWindowManager.shared.show() }
                Spacer()
                Button("设置…") { onClose(); SettingsWindowManager.shared.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            .buttonStyle(.borderless)
            Button("退出 LumenFocus") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 340)
        .background(Color.LumenFocus.backgroundPrimary)
    }

    private var statusTitle: String {
        switch appState.currentPhase {
        case .working: return L("下次休息")
        case .reminderDue: return L("休息提醒")
        case .triggeringRest: return L("准备离屏休息")
        case .resting: return L("剩余休息时间")
        case .paused: return L("提醒已暂停")
        case .autoSuspended: return L("提醒暂缓")
        }
    }

    private var statusValue: String {
        switch appState.currentPhase {
        case .working: return appState.nextReminderDate.map(reminderClockText) ?? appState.formattedRemainingTime
        case .reminderDue: return L("该休息一下了")
        case .triggeringRest, .resting: return appState.formattedRemainingTime
        case .paused(let until):
            switch until {
            case .duration(let date): return reminderClockText(date)
            case .endOfDay: return L("至今日结束")
            }
        case .autoSuspended: return L("暂不打扰")
        }
    }

    private var statusDetail: String {
        switch appState.currentPhase {
        case .working:
            if let detail = appState.environmentDetail, !detail.isEmpty { return detail }
            return String(format: L("还有 %d 分钟"), max(1, Int(ceil(Double(appState.remainingSeconds) / 60))))
        case .reminderDue: return L("准备好再开始，当前工作不会被遮挡。")
        case .triggeringRest, .resting: return L("看向屏幕之外。你可以随时结束或延后。")
        case .paused(let until):
            switch until {
            case .duration: return L("届时恢复提醒，工作时长继续累计。若已到点，会留出缓冲。")
            case .endOfDay: return L("明天恢复提醒，也可随时手动恢复。")
            }
        case .autoSuspended:
            return appState.environmentDetail ?? L("环境变化后自动恢复，也可手动继续。")
        }
    }

    @ViewBuilder private var phaseControls: some View {
        switch appState.currentPhase {
        case .working, .reminderDue:
            Button {
                onClose(); TimerManager.shared.triggerManualRest()
            } label: {
                Text(verbatim: L(appState.currentPhase == .reminderDue ? "开始休息" : "现在休息"))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.LumenFocus.ink)
            .frame(maxWidth: .infinity)
            HStack {
                Menu {
                    ForEach([2, 5, 10], id: \.self) { minutes in
                        Button {
                            onClose(); TimerManager.shared.snoozeReminder(by: TimeInterval(minutes * 60))
                        } label: {
                            Text(verbatim: delayTitle(minutes))
                        }
                    }
                    if appState.currentPhase == .reminderDue {
                        Divider()
                        Button("跳过本次") { onClose(); TimerManager.shared.skipReminder() }
                    }
                } label: {
                    Text(verbatim: L(appState.currentPhase == .reminderDue ? "稍后再提醒" : "延后本次"))
                }
                pauseMenu
            }
        case .paused:
            Button("恢复提醒") { onClose(); TimerManager.shared.resume() }
                .buttonStyle(.borderedProminent)
                .tint(Color.LumenFocus.ink)
        case .autoSuspended:
            Button("现在休息") { onClose(); TimerManager.shared.triggerManualRest() }
                .buttonStyle(.bordered)
            pauseMenu
        case .triggeringRest, .resting:
            Button("结束休息") { onClose(); RestController.shared.cancelRest() }
                .buttonStyle(.borderedProminent)
                .tint(Color.LumenFocus.ink)
            Button("2 分钟后再提醒") { onClose(); RestController.shared.snooze(by: 120) }
                .buttonStyle(.bordered)
        }
    }

    private var pauseMenu: some View {
        Menu("暂停提醒") {
            ForEach([15, 60], id: \.self) { minutes in
                Button {
                    onClose(); TimerManager.shared.pause(duration: TimeInterval(minutes * 60))
                } label: {
                    Text(verbatim: String(format: L("暂停至 %@"), reminderClockText(Date().addingTimeInterval(TimeInterval(minutes * 60)))))
                }
            }
            Button("至今日结束") { onClose(); TimerManager.shared.pause(duration: nil) }
        }
    }

    private func delayTitle(_ minutes: Int) -> String {
        let base = appState.currentPhase == .reminderDue ? Date() : (appState.nextReminderDate ?? Date())
        let date = base.addingTimeInterval(TimeInterval(minutes * 60))
        return String(format: L("延后 %d 分钟 · %@"), minutes, reminderClockText(date))
    }
}

func reminderClockText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    return formatter.string(from: date)
}
