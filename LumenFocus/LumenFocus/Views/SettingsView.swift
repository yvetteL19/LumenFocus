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
        case rhythm, general
    }

    init(showGeneral: Bool = false) {
        _selectedTab = State(initialValue: showGeneral || ProcessInfo.processInfo.arguments.contains("--show-settings-general") ? .general : .rhythm)
    }

    private var remindersBinding: Binding<Bool> {
        Binding(get: { settings.remindersEnabled }, set: {
            if $0 { TimerManager.shared.startReminders() } else { TimerManager.shared.stopReminders() }
        })
    }

    private var launchBinding: Binding<Bool> {
        Binding(get: { settings.launchAtLogin }, set: applyLaunchAtLogin)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            rhythmTab
                .tabItem { Label("节奏", systemImage: "timer") }
                .tag(SettingsTab.rhythm)
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
                ReminderDurationPicker(workMinutes: $settings.workDurationMinutes)
                ReminderDurationPicker(restSeconds: $settings.restDurationSeconds)
            } header: {
                Text("提醒节奏")
            } footer: {
                helpText("新的休息时长从下次休息生效。")
            }

            Section {
                Toggle("自动提醒", isOn: remindersBinding)
                if settings.remindersEnabled {
                    if appState.isPaused {
                        if let until = settings.remindersPausedUntil {
                            Text(verbatim: String(format: L("暂停至 %@"), ReminderPresentation.clockText(until)))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button("恢复提醒") { TimerManager.shared.resume() }
                    } else if appState.currentPhase == .working {
                        Button("休息一下") { TimerManager.shared.triggerManualRest() }
                    } else if appState.isResting {
                        Button("返回工作") { TimerManager.shared.cancelCurrentRest() }
                    }
                    ReminderPauseMenu(titleKey: appState.isPaused ? "调整暂停时间" : "暂停提醒")
                }
            } footer: {
                helpText(!settings.remindersEnabled
                    ? "已停止。开启后会按设定间隔提醒。"
                    : (appState.isPaused ? "暂停结束后重新计时。" : "到点自动渐暗，按任意键即可结束。"))
            }

            Section {
                Button {
                    isPlayingPreview = true
                    OnboardingDemo.shared.play(totalDuration: 10) { isPlayingPreview = false }
                } label: {
                    Text(verbatim: L(isPlayingPreview ? "演示中…" : "预览渐暗"))
                }
                .disabled(isPlayingPreview || appState.isResting)
                .help(L("预览持续 10 秒，仅在当前屏幕显示；按任意键可结束。"))
            } header: {
                Text("休息一下")
            } footer: {
                helpText("按任意键可立即结束，休息时长结束后屏幕自动变亮。")
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
