import SwiftUI

/// The next reminder and the user's controls are the primary menu-bar experience.
struct MenuBarPopoverView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var settings = AppSettings.shared
    var onClose: () -> Void = {}

    private var presentation: ReminderPresentation {
        ReminderPresentation(phase: appState.currentPhase, remainingSeconds: appState.remainingSeconds,
                             nextReminderDate: appState.nextReminderDate, environmentDetail: appState.environmentDetail,
                             restDurationSeconds: settings.restDurationSeconds, lastRestOutcome: appState.lastRestOutcome)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusHeader
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
            }
            Text(verbatim: presentation.value())
                .font(.system(size: appState.currentPhase == .reminderDue || appState.isResting ? 23 : 30,
                              weight: .medium, design: .rounded))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: presentation.outcomeText() ?? presentation.detail())
                .font(.system(size: 12))
                .foregroundColor(Color.LumenFocus.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if presentation.outcomeText() != nil, let detail = appState.environmentDetail, !detail.isEmpty {
                Text(verbatim: detail)
                    .font(.system(size: 12))
                    .foregroundColor(Color.LumenFocus.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reminder.status")
    }

    @ViewBuilder private var phaseControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            primaryButton
            switch appState.currentPhase {
            case .working, .reminderDue:
                VStack(alignment: .leading, spacing: 10) {
                    delayMenu
                    pauseMenu
                }
            case .paused:
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        perform(.startRest)
                    } label: {
                        Text(verbatim: L("休息并恢复提醒"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint(Text(verbatim: L("开始休息会结束暂停，之后按当前节奏提醒。")))
                    .accessibilityIdentifier("reminder.breakWhilePaused")
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
                    RestController.shared.snooze(by: ReminderPresentation.defaultSnoozeSeconds)
                } label: {
                    Text(verbatim: ReminderPresentation.defaultSnoozeTitle())
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
            Text(verbatim: presentation.primaryTitle())
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
            ForEach(ReminderPresentation.delayChoices, id: \.self) { minutes in
                Button {
                    onClose()
                    TimerManager.shared.snoozeReminder(by: TimeInterval(minutes * 60))
                } label: {
                    Text(verbatim: presentation.delayOptionTitle(minutes: minutes))
                }
            }
            if appState.currentPhase == .reminderDue {
                Divider()
                Button {
                    onClose()
                    TimerManager.shared.skipReminder()
                } label: {
                    Text(verbatim: ReminderPresentation.skipTitle(workMinutes: settings.workDurationMinutes))
                }
            }
        } label: {
            Text(verbatim: L(appState.currentPhase == .reminderDue ? "稍后再提醒" : "延后本次"))
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("reminder.snooze")
    }

    private var pauseMenu: some View {
        Menu {
            ForEach(ReminderPresentation.pauseChoices, id: \.self) { minutes in
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
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("reminder.pause")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: localizedCompletedBreaksToday(appState.todayRestCount))
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
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    onClose()
                    SettingsWindowManager.shared.showSettings()
                } label: {
                    Text(verbatim: L("设置…"))
                        .fixedSize(horizontal: false, vertical: true)
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
