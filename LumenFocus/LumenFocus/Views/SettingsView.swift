import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var shortcuts = GlobalShortcutManager.shared
    @ObservedObject private var appState = AppState.shared
    @State private var selectedTab: SettingsTab
    @State private var isPlayingPreview = false
    @State private var showResetConfirmation = false
    @State private var showSystemError = false
    @State private var isRelaunching = false
    @State private var systemError = ""
    @State private var systemErrorTitle = ""

    private enum SettingsTab: Hashable {
        case rhythm, avoidance, general
    }

    init(showGeneral: Bool = false) {
        _selectedTab = State(initialValue: showGeneral || ProcessInfo.processInfo.arguments.contains("--show-settings-general") ? .general : .rhythm)
    }

    private var workBinding: Binding<Double> {
        Binding(get: { Double(settings.workDurationMinutes) }, set: { settings.workDurationMinutes = Int($0) })
    }

    private var launchBinding: Binding<Bool> {
        Binding(get: { settings.launchAtLogin }, set: applyLaunchAtLogin)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            rhythmTab
                .tabItem { Label("提醒", systemImage: "timer") }
                .tag(SettingsTab.rhythm)
            avoidanceTab
                .tabItem { Label("提醒避让", systemImage: "moon") }
                .tag(SettingsTab.avoidance)
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }
                .tag(SettingsTab.general)
        }
        .padding(12)
        .frame(minWidth: 520, minHeight: 480)
        .onAppear(perform: refreshLaunchAtLogin)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLaunchAtLogin()
        }
        .alert(Text(verbatim: systemErrorTitle), isPresented: $showSystemError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(verbatim: systemError)
                .fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog("确定要恢复默认设置吗？", isPresented: $showResetConfirmation) {
            Button("恢复", role: .destructive) {
                settings.resetToDefaults()
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
                    LabeledContent("提醒间隔", value: restDurationText(settings.workDurationMinutes * 60))
                        .monospacedDigit()
                    Slider(value: workBinding,
                           in: Double(AppSettings.workDurationRange.lowerBound)...Double(AppSettings.workDurationRange.upperBound), step: 5)
                        .tint(Color.LumenFocus.ink)
                        .accessibilityLabel(Text("提醒间隔"))
                        .accessibilityValue(Text(verbatim: restDurationText(settings.workDurationMinutes * 60)))
                }
                BreakDurationPicker(seconds: $settings.restDurationSeconds)
            } header: {
                Text("提醒节奏")
            } footer: {
                helpText("新的休息时长从下次休息生效。")
            }

            Section {
                Picker("提醒方式", selection: $settings.reminderMode) {
                    ForEach(ReminderMode.allCases) { mode in
                        Text(verbatim: mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                Button {
                    isPlayingPreview = true
                    OnboardingDemo.shared.play(totalDuration: 10) { isPlayingPreview = false }
                } label: {
                    Text(verbatim: L(isPlayingPreview ? "演示中…" : "预览渐暗"))
                }
                .disabled(isPlayingPreview || appState.isResting)
                .help(L("预览持续 10 秒，仅在当前屏幕显示；按 Esc 或点击可结束。"))
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
                helpText("锁屏或睡眠时自动暂停工作计时，不受提醒规则影响。")
            }

            Section {
                Toggle("会议应用", isOn: $settings.detectVideoCall)
                    .disabled(!settings.enableSmartDetection)
                Toggle("演示与媒体应用", isOn: $settings.detectFullscreen)
                    .disabled(!settings.enableSmartDetection)
                DisclosureGroup("查看包含的应用") {
                    VStack(alignment: .leading, spacing: 12) {
                        supportedApps("会议应用", names: ForegroundAppRuleResolver.meetingApps.map(\.name))
                        supportedApps("演示与媒体应用", names: ForegroundAppRuleResolver.presentationApps.map(\.name))
                        helpText("根据当前在前台的应用暂缓提醒，不识别真实通话、共享或全屏状态。")
                    }
                    .padding(.vertical, 8)
                }
            } header: {
                Text("前台应用规则")
            } footer: {
                helpText("这些应用在前台时暂缓提醒，工作计时继续。离开后会先留出缓冲。")
            }

            if settings.reminderMode == .immersive {
                Section {
                    Toggle("1 分钟无操作时，改用轻提醒", isOn: $settings.detectIdle)
                        .disabled(!settings.enableSmartDetection)
                } footer: {
                    helpText("无操作时不自动渐暗屏幕，工作计时继续。")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var generalTab: some View {
        Form {
            Section("外观与启动") {
                Toggle("登录 Mac 时启动", isOn: launchBinding)
                Toggle("菜单栏显示剩余分钟数字", isOn: $settings.showRemainingMinutesInMenuBar)
            }

            Section {
                if shortcuts.isRegistered {
                    LabeledContent("开始或提前结束休息", value: "⌘⌥E")
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
                if settings.hasPendingLanguageChange {
                    Button("重启以应用语言") { relaunchApp() }
                        .disabled(isRelaunching)
                }
            } header: {
                Text("语言")
            } footer: {
                if settings.hasPendingLanguageChange { helpText("切换语言需在重启 App 后生效。") }
            }

            Section("帮助与隐私") {
                if let url = URL(string: AppSettings.privacyPolicyURLString) {
                    Link("隐私政策", destination: url)
                }
                if let mail = URL(string: "mailto:\(AppSettings.supportEmail)") {
                    Link("联系支持", destination: mail)
                }
                LabeledContent("版本", value: appVersionString)
            }
            Section {
                Button("恢复默认", role: .destructive) { showResetConfirmation = true }
            } footer: {
                helpText("只恢复偏好设置，不删除工作与休息记录。")
            }
        }
        .formStyle(.grouped)
    }

    private func supportedApps(_ title: String, names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: L(title)).fontWeight(.medium)
            Text(verbatim: names.joined(separator: " · "))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            systemErrorTitle = L("未能更改登录启动设置")
            systemError = L("未能更改登录启动设置。请在系统设置的登录项中检查。")
            showSystemError = true
        }
    }

    private func relaunchApp() {
        guard !isRelaunching else { return }
        isRelaunching = true
        let intent: RelaunchIntent
        do {
            guard let launchDate = NSRunningApplication.current.launchDate,
                  let bundleID = Bundle.main.bundleIdentifier else { throw CocoaError(.coderInvalidValue) }
            intent = try RelaunchIntentStore.shared.prepare(previousPID: ProcessInfo.processInfo.processIdentifier,
                                                           previousLaunchDate: launchDate, bundleIdentifier: bundleID)
        } catch {
            isRelaunching = false
            systemErrorTitle = L("未能重新启动")
            systemError = L("未能重新打开 LumenFocus，请退出后手动重新打开。")
            showSystemError = true
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { application, error in
            DispatchQueue.main.async {
                isRelaunching = false
                if let error {
                    RelaunchIntentStore.shared.cancel(token: intent.token)
                    systemErrorTitle = L("未能重新启动")
                    systemError = error.localizedDescription
                    showSystemError = true
                } else if let application,
                          application.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    NSApp.terminate(nil)
                } else {
                    RelaunchIntentStore.shared.cancel(token: intent.token)
                    systemErrorTitle = L("未能重新启动")
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
