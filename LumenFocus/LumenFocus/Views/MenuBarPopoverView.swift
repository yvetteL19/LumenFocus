import SwiftUI

/// The next reminder and the user's controls are the primary menu-bar experience.
struct MenuBarPopoverView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var settings = AppSettings.shared
    var onClose: () -> Void = {}

    private var presentation: ReminderPresentation {
        ReminderPresentation(phase: appState.currentPhase, remainingSeconds: appState.remainingSeconds,
                             nextReminderDate: appState.nextReminderDate, environmentDetail: appState.environmentDetail)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusHeader
            rhythmSummary
            phaseControls
            Divider()
            footer
        }
        .padding(20)
        .frame(width: 350)
        .background(Color.LumenFocus.backgroundPrimary)
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label {
                    Text(verbatim: L(presentation.titleKey))
                } icon: {
                    Image(systemName: presentation.symbolName)
                        .accessibilityHidden(true)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.LumenFocus.textSecondary)
                Spacer()
                Text(verbatim: settings.reminderMode.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.LumenFocus.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.LumenFocus.backgroundSecondary, in: Capsule())
            }
            Text(verbatim: presentation.value())
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: presentation.detail())
                .font(.system(size: 12))
                .foregroundColor(Color.LumenFocus.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reminder.status")
    }

    private var rhythmSummary: some View {
        Text(verbatim: ReminderPresentation.rhythmSummary(workMinutes: settings.workDurationMinutes,
                                                          restSeconds: settings.restDurationSeconds))
            .font(.system(size: 12))
            .foregroundColor(Color.LumenFocus.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("reminder.rhythm")
    }

    @ViewBuilder private var phaseControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            primaryButton
            switch appState.currentPhase {
            case .working, .reminderDue:
                HStack(spacing: 10) {
                    delayMenu
                    Spacer(minLength: 8)
                    pauseMenu
                }
            case .paused:
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Button {
                        perform(.startRest)
                    } label: {
                        Text(verbatim: L("休息并恢复提醒"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint(Text(verbatim: L("开始休息会结束暂停，之后按当前节奏提醒。")))
                    .accessibilityIdentifier("reminder.breakWhilePaused")
                    Spacer(minLength: 4)
                    pauseMenu
                }
                Text(verbatim: L("开始休息会结束暂停，之后按当前节奏提醒。"))
                    .font(.system(size: 11))
                    .foregroundColor(Color.LumenFocus.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .autoSuspended:
                HStack {
                    Spacer()
                    pauseMenu
                }
            case .triggeringRest, .resting:
                Button {
                    onClose()
                    RestController.shared.snooze(by: 120)
                } label: {
                    Text(verbatim: L("2 分钟后再提醒"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("reminder.postponeRest")
            }
        }
        .font(.system(size: 12))
    }

    private var primaryButton: some View {
        Button {
            perform(presentation.primaryAction)
        } label: {
            Text(verbatim: L(presentation.primaryTitleKey))
                .font(.system(size: 13, weight: .semibold))
                // Expanding the label expands the native button's actual hit area and fill.
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.LumenFocus.ink)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("reminder.primary")
    }

    private var delayMenu: some View {
        Menu {
            ForEach([2, 5, 10], id: \.self) { minutes in
                Button {
                    onClose()
                    TimerManager.shared.snoozeReminder(by: TimeInterval(minutes * 60))
                } label: {
                    let date = presentation.delayedReminderDate(minutes: minutes)
                    Text(verbatim: String(format: L("延后 %d 分钟 · %@"), minutes, reminderClockText(date)))
                }
            }
            if appState.currentPhase == .reminderDue {
                Divider()
                Button {
                    onClose()
                    TimerManager.shared.skipReminder()
                } label: {
                    Text(verbatim: L("跳过本次"))
                }
            }
        } label: {
            Text(verbatim: L(appState.currentPhase == .reminderDue ? "稍后再提醒" : "延后本次"))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityIdentifier("reminder.snooze")
    }

    private var pauseMenu: some View {
        Menu {
            ForEach([15, 60], id: \.self) { minutes in
                Button {
                    onClose()
                    TimerManager.shared.pause(duration: TimeInterval(minutes * 60))
                } label: {
                    Text(verbatim: ReminderPresentation.pauseOptionTitle(minutes: minutes))
                }
            }
            Button {
                onClose()
                TimerManager.shared.pause(duration: nil)
            } label: {
                Text(verbatim: L("至今日结束"))
            }
        } label: {
            Text(verbatim: L(presentation.pauseMenuTitleKey))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityIdentifier("reminder.pause")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: String(format: L("今日完成 %d 次休息 · 已计时 %@"),
                                  appState.todayRestCount, appState.formattedTodayWorkDuration))
                .font(.system(size: 11))
                .foregroundColor(Color.LumenFocus.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("reminder.today")
            HStack(spacing: 14) {
                Button {
                    onClose()
                    StatisticsWindowManager.shared.show()
                } label: {
                    Text(verbatim: L("详细统计"))
                }
                Button {
                    onClose()
                    SettingsWindowManager.shared.showSettings()
                } label: {
                    Text(verbatim: L("设置…"))
                }
                .keyboardShortcut(",", modifiers: .command)
                Spacer(minLength: 8)
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text(verbatim: L("退出"))
                }
                .keyboardShortcut("q", modifiers: .command)
                .accessibilityLabel(Text(verbatim: L("退出 LumenFocus")))
            }
            .font(.system(size: 12))
            .buttonStyle(.borderless)
        }
    }

    private func perform(_ action: ReminderPresentation.Action) {
        onClose()
        switch action {
        case .startRest: TimerManager.shared.triggerManualRest()
        case .resumeReminders: TimerManager.shared.resume()
        case .endRest: RestController.shared.cancelRest()
        }
    }
}

func reminderClockText(_ date: Date) -> String {
    ReminderPresentation.clockText(date)
}
