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
                .font(.system(size: appState.isResting ? 23 : 30,
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
            if !appState.isAutoSuspended {
                primaryButton
            }
            switch appState.currentPhase {
            case .working:
                Button {
                    onClose()
                    TimerManager.shared.skipReminder()
                } label: {
                    Text(verbatim: ReminderPresentation.skipTitle(workMinutes: settings.workDurationMinutes))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("reminder.skip")
                pauseMenu
                stopButton
            case .paused:
                pauseMenu
                stopButton
            case .autoSuspended:
                pauseMenu
                stopButton
            case .triggeringRest, .resting:
                pauseMenu
                stopButton
            case .stopped:
                EmptyView()
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

    private var pauseMenu: some View {
        ReminderPauseMenu(titleKey: presentation.pauseMenuTitleKey, onSelect: onClose)
            .accessibilityIdentifier("reminder.pause")
    }

    private var stopButton: some View {
        Button {
            onClose()
            TimerManager.shared.stopReminders()
        } label: {
            Text("停止提醒")
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("reminder.stop")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Button {
                    onClose()
                    StatisticsWindowManager.shared.show()
                } label: {
                    Text(verbatim: L("记录"))
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
        case .startReminders: TimerManager.shared.startReminders()
        case .startRest: TimerManager.shared.triggerManualRest()
        case .resumeReminders: TimerManager.shared.resume()
        case .endRest: TimerManager.shared.cancelCurrentRest()
        }
    }
}

func reminderClockText(_ date: Date) -> String {
    ReminderPresentation.clockText(date)
}
