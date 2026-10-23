import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var shortcuts = GlobalShortcutManager.shared
    @ObservedObject private var appState = AppState.shared
    @State private var selectedTab: SettingsTab = .rhythm
    @State private var showAllRestDurations = false
    @State private var showResetConfirmation = false
    @State private var showSystemError = false
    @State private var isRelaunching = false
    @State private var systemError = ""

    private enum SettingsTab: Hashable {
        case rhythm, avoidance, general, support
    }

    private let commonRestDurations = [20, 60, 300]

    private var workBinding: Binding<Double> {
        Binding(get: { Double(settings.workDurationMinutes) }, set: { settings.workDurationMinutes = Int($0) })
    }

    private var launchBinding: Binding<Bool> {
        Binding(get: { settings.launchAtLogin }, set: applyLaunchAtLogin)
    }

    /// Selecting Other reveals all supported durations without changing the timer.
    private var restPresetBinding: Binding<Int> {
        Binding(
            get: {
                showAllRestDurations || !commonRestDurations.contains(settings.restDurationSeconds)
                    ? -1 : settings.restDurationSeconds
            },
            set: { value in
                showAllRestDurations = value == -1
                if value != -1 { settings.restDurationSeconds = value }
            }
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            rhythmTab
                .tabItem { Label("节奏", systemImage: "timer") }
                .tag(SettingsTab.rhythm)
            avoidanceTab
                .tabItem { Label("勿扰规则", systemImage: "moon") }
                .tag(SettingsTab.avoidance)
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            supportTab
                .tabItem { Label("数据与支持", systemImage: "info.circle") }
                .tag(SettingsTab.support)
        }
        .padding(12)
        .frame(minWidth: 520, minHeight: 480)
        .onAppear(perform: refreshLaunchAtLogin)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLaunchAtLogin()
        }
        .alert("无法应用系统设置", isPresented: $showSystemError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(verbatim: systemError)
                .fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog("确定要恢复默认设置吗？", isPresented: $showResetConfirmation) {
            Button("恢复", role: .destructive) {
                settings.resetToDefaults()
                showAllRestDurations = false
                applyLaunchAtLogin(settings.launchAtLogin)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只恢复偏好设置，不删除工作与休息记录。")
        }
    }

    private var rhythmTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("工作时长", value: String(format: L("%d 分钟"), settings.workDurationMinutes))
                        .monospacedDigit()
                    Slider(value: workBinding, in: 15...120, step: 5)
                        .tint(Color.LumenFocus.ink)
                        .accessibilityLabel(Text("工作时长"))
                        .accessibilityValue(Text(verbatim: String(format: L("%d 分钟"), settings.workDurationMinutes)))
                }
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("休息时长", value: restDurationText(settings.restDurationSeconds))
                        .monospacedDigit()
                    Picker("常用休息时长", selection: restPresetBinding) {
                        ForEach(commonRestDurations, id: \.self) { seconds in
                            Text(verbatim: restDurationText(seconds)).tag(seconds)
                        }
                        Text("其他时长").tag(-1)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityLabel(Text("常用休息时长"))
                    if restPresetBinding.wrappedValue == -1 {
                        Picker("选择休息时长", selection: $settings.restDurationSeconds) {
                            ForEach(restDurationChoices(including: settings.restDurationSeconds), id: \.self) { seconds in
                                Text(verbatim: restDurationText(seconds)).tag(seconds)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            } header: {
                Text("工作与休息")
            } footer: {
                helpText("调整节奏后，菜单栏会显示新的提醒时间。渐暗渐亮不占用休息时长。")
            }

            Section {
                Picker("提醒方式", selection: $settings.reminderMode) {
                    ForEach(ReminderMode.allCases) { mode in
                        Text(verbatim: mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("如何开始休息")
            } footer: {
                helpText(settings.reminderMode == .gentle
                    ? "到点显示轻提醒。你点击开始后，才会进入离屏休息。"
                    : "到点自动渐暗所有屏幕。休息全程可结束或延后。")
            }

            Section {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("离屏休息")
                            .fontWeight(.medium)
                        Text(verbatim: restDurationText(settings.restDurationSeconds))
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button {
                        TimerManager.shared.triggerManualRest()
                    } label: {
                        Text(verbatim: L(appState.isResting ? "正在休息" : (appState.isPaused ? "休息并恢复提醒" : "现在休息")))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.LumenFocus.ink)
                    .disabled(appState.isResting)
                }
            } footer: {
                helpText(appState.isPaused
                    ? "开始休息会结束暂停，之后按当前节奏提醒。"
                    : "直接开始当前设定的离屏休息。可随时结束或延后。")
            }
        }
        .formStyle(.grouped)
    }

    private var avoidanceTab: some View {
        Form {
            Section {
                Toggle("启用提醒规则", isOn: $settings.enableSmartDetection)
            } footer: {
                helpText("关闭提醒规则后，锁屏与睡眠仍会暂停工作计时。")
            }

            Section {
                Toggle("会议应用", isOn: $settings.detectVideoCall)
                Toggle("演示与媒体应用", isOn: $settings.detectFullscreen)
            } header: {
                Text("前台应用规则")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    helpText("根据当前在前台的应用暂缓提醒，不识别真实通话、共享或全屏状态。")
                    helpText("这类暂缓不会停止工作计时。切换到其他应用后，会先留出缓冲再提醒。")
                }
            }
            .disabled(!settings.enableSmartDetection)

            Section {
                Toggle("无操作时使用轻提醒", isOn: $settings.detectIdle)
                    .disabled(!settings.enableSmartDetection)
                LabeledContent("锁屏与睡眠", value: L("自动处理"))
            } header: {
                Text("无操作与离开电脑")
            } footer: {
                helpText("无操作不等于休息，只改用轻提醒；锁屏或睡眠才暂停工作计时。")
            }
        }
        .formStyle(.grouped)
    }

    private var generalTab: some View {
        Form {
            Section("外观与启动") {
                Toggle("开机时自动启动", isOn: launchBinding)
                Toggle("菜单栏显示剩余分钟数字", isOn: $settings.showRemainingMinutesInMenuBar)
            }

            Section {
                if shortcuts.isRegistered {
                    LabeledContent("开始或结束休息", value: "⌘⌥E")
                } else {
                    helpText(shortcuts.registrationError ?? "全局快捷键暂不可用。仍可使用菜单栏、休息按钮和 Esc。")
                }
            } header: {
                Text("键盘与辅助功能")
            } footer: {
                helpText("动画跟随系统的减少动态效果设置。")
            }

            Section {
                Picker("语言", selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(verbatim: language.displayName).tag(language)
                    }
                }
                Button("重启以应用语言") { relaunchApp() }
                    .disabled(isRelaunching)
            } header: {
                Text("语言")
            } footer: {
                helpText("切换语言需在重启 App 后生效。")
            }

            Section {
                Button("恢复默认", role: .destructive) { showResetConfirmation = true }
            } footer: {
                helpText("只恢复偏好设置，不删除工作与休息记录。")
            }
        }
        .formStyle(.grouped)
    }

    private var supportTab: some View {
        Form {
            Section {
                Button("查看详细统计") { StatisticsWindowManager.shared.show() }
            } header: {
                Text("工作与休息记录")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    helpText("仅记录计时工作与完成的休息，不代表实际用眼时长或健康改善。")
                    helpText("记录保存在这台 Mac 上，可在统计窗口导出。")
                }
            }

            Section("帮助与隐私") {
                Button("重新体验引导") { OnboardingWindowManager.shared.showOnboarding(completion: {}) }
                if let url = URL(string: AppSettings.privacyPolicyURLString) {
                    Link("隐私政策", destination: url)
                }
                if let mail = URL(string: "mailto:\(AppSettings.supportEmail)") {
                    Link("联系支持", destination: mail)
                }
            }

            Section("关于 LumenFocus") {
                LabeledContent("版本", value: appVersionString)
            }
        }
        .formStyle(.grouped)
    }

    /// Footer and explanatory copy must remain readable when the window is narrowed
    /// or when an English translation is longer than the source string.
    private func helpText(_ key: String) -> some View {
        Text(verbatim: L(key))
            .font(.callout)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshLaunchAtLogin() {
        let enabled = LaunchAtLoginManager.shared.isEnabled()
        if settings.launchAtLogin != enabled { settings.launchAtLogin = enabled }
    }

    private func applyLaunchAtLogin(_ desired: Bool) {
        let manager = LaunchAtLoginManager.shared
        if manager.isEnabled() == desired {
            settings.launchAtLogin = desired
            return
        }
        let success = desired ? manager.enable() : manager.disable()
        settings.launchAtLogin = manager.isEnabled()
        if !success || settings.launchAtLogin != desired {
            systemError = L("系统未能应用开机启动设置。请在系统设置的登录项中检查；当前状态未被更改。")
            showSystemError = true
        }
    }

    private func relaunchApp() {
        guard !isRelaunching else { return }
        isRelaunching = true
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { application, error in
            DispatchQueue.main.async {
                isRelaunching = false
                if let error {
                    systemError = error.localizedDescription
                    showSystemError = true
                } else if application != nil {
                    NSApp.terminate(nil)
                } else {
                    systemError = L("未能重新打开 LumenFocus，请退出后手动重新打开。")
                    showSystemError = true
                }
            }
        }
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
