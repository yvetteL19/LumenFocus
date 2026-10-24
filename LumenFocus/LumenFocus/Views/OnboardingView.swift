import SwiftUI

/// Editing is isolated from saved preferences until the single start action.
struct OnboardingView: View {
    @State private var draft = OnboardingDraft(settings: .shared, launchAtLogin: LaunchAtLoginManager.shared.isEnabled())
    @State private var isEditingRhythm = false
    @State private var isPlayingDemo = false
    @State private var launchError = false
    private let isInitialSetup = !AppSettings.shared.hasCompletedOnboarding

    private var workBinding: Binding<Double> {
        Binding(get: { Double(draft.workMinutes) }, set: { draft.workMinutes = Int($0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("给工作留一点离屏时间")
                            .font(.system(size: 27, weight: .medium))
                    }

                    GroupBox {
                        DisclosureGroup(isExpanded: $isEditingRhythm) {
                            VStack(alignment: .leading, spacing: 16) {
                                LabeledContent("提醒间隔", value: restDurationText(draft.workMinutes * 60))
                                Slider(value: workBinding,
                                       in: Double(AppSettings.workDurationRange.lowerBound)...Double(AppSettings.workDurationRange.upperBound), step: 5)
                                    .tint(Color.LumenFocus.ink)
                                    .accessibilityLabel(Text("提醒间隔"))
                                    .accessibilityValue(Text(verbatim: restDurationText(draft.workMinutes * 60)))
                                BreakDurationPicker(seconds: $draft.restSeconds)
                            }
                            .padding(.top, 16)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("提醒节奏").fontWeight(.medium)
                                Text(verbatim: String(format: L("每 %@ 提醒 · 每次休息 %@"),
                                                      restDurationText(draft.workMinutes * 60), restDurationText(draft.restSeconds)))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(8)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Picker("提醒方式", selection: $draft.reminderMode) {
                            ForEach(ReminderMode.allCases) { mode in
                                Text(verbatim: mode.displayName).tag(mode)
                            }
                        }
                        Text(verbatim: L(draft.reminderMode == .gentle
                            ? "到点显示轻提醒。你点击开始后，才会进入离屏休息。"
                            : "到点自动渐暗所有屏幕。休息全程可结束或延后。"))
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            isPlayingDemo = true
                            OnboardingDemo.shared.play(totalDuration: 10) { isPlayingDemo = false }
                        } label: {
                            Label {
                                Text(verbatim: L(isPlayingDemo ? "演示中…" : "预览渐暗"))
                            } icon: { Image(systemName: "play.circle") }
                        }
                        .disabled(isPlayingDemo)
                        .help(L("预览持续 10 秒，仅在当前屏幕显示；按 Esc 或点击可结束。"))
                    }

                    Toggle("登录 Mac 时启动", isOn: $draft.launchAtLogin)
                    Text("之后可以在菜单栏调整。记录只保存在这台 Mac。")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28)
            }
            Divider()
            HStack {
                Button {
                    OnboardingWindowManager.shared.close()
                } label: {
                    Text(verbatim: L(isInitialSetup ? "稍后设置并退出" : "取消"))
                }
                .keyboardShortcut(.cancelAction)
                Spacer(minLength: 16)
                Button("开始提醒", action: saveAndStart)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.LumenFocus.ink)
            }
            .disabled(isPlayingDemo)
            .padding(24)
        }
        .frame(minWidth: 460, minHeight: 440)
        .background(Color.LumenFocus.backgroundPrimary)
        .alert("未能更改登录启动设置", isPresented: $launchError) {
            Button("好", role: .cancel) {}
        } message: {
            Text("请在系统设置的登录项中检查。已显示当前状态；你可以再次点击开始提醒。")
        }
    }

    private func saveAndStart() {
        let manager = LaunchAtLoginManager.shared
        guard draft.commit(to: .shared, readLaunchAtLogin: manager.isEnabled,
                           setLaunchAtLogin: { $0 ? manager.enable() : manager.disable() }) else {
            draft.launchAtLogin = manager.isEnabled()
            launchError = true
            return
        }
        OnboardingWindowManager.shared.finishSetup()
    }
}
