import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var shortcuts = GlobalShortcutManager.shared
    @State private var showResetConfirmation = false
    @State private var showSystemError = false
    @State private var systemError = ""

    private var workBinding: Binding<Double> {
        Binding(get: { Double(settings.workDurationMinutes) }, set: { settings.workDurationMinutes = Int($0) })
    }
    private var launchBinding: Binding<Bool> {
        Binding(get: { settings.launchAtLogin }, set: applyLaunchAtLogin)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("工作时长", value: String(format: L("%d 分钟"), settings.workDurationMinutes))
                    Slider(value: workBinding, in: 15...120, step: 5)
                        .tint(Color.LumenFocus.ink)
                        .accessibilityLabel(Text("工作时长"))
                        .accessibilityValue(Text(verbatim: String(format: L("%d 分钟"), settings.workDurationMinutes)))
                }
                Picker("休息时长", selection: $settings.restDurationSeconds) {
                    ForEach(restDurationChoices(including: settings.restDurationSeconds), id: \.self) { seconds in
                        Text(verbatim: restDurationText(seconds)).tag(seconds)
                    }
                }
            } header: { Text("时间配置") } footer: {
                Text("调整节奏后，菜单栏会显示新的提醒时间。渐暗渐亮不占用休息时长。")
            }
            Section {
                Picker("提醒方式", selection: $settings.reminderMode) {
                    ForEach(ReminderMode.allCases) { mode in Text(verbatim: mode.displayName).tag(mode) }
                }
                if shortcuts.isRegistered {
                    LabeledContent("开始或结束休息", value: "⌘⌥E")
                } else {
                    Text("全局快捷键暂不可用。仍可使用菜单栏、休息按钮和 Esc。")
                        .foregroundColor(.secondary)
                }
                Button("现在休息") { TimerManager.shared.triggerManualRest() }
            } header: { Text("休息体验") } footer: {
                Text(verbatim: L(settings.reminderMode == .gentle ? "到点显示轻提醒。你点击开始后，才会进入离屏休息。" : "到点自动渐暗所有屏幕。休息全程可结束或延后。"))
                Text("动画跟随系统的减少动态效果设置。")
            }
            smartDetectionSection
            Section("外观与启动") {
                Toggle("开机时自动启动", isOn: launchBinding)
                Toggle("菜单栏显示剩余分钟数字", isOn: $settings.showRemainingMinutesInMenuBar)
            }
            Section {
                Picker("语言", selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in Text(verbatim: language.displayName).tag(language) }
                }
                Button("重启以应用语言") { relaunchApp() }
            } header: { Text("语言") } footer: { Text("切换语言需在重启 App 后生效。") }
            Section("统计数据") {
                Button("查看详细统计") { StatisticsWindowManager.shared.show() }
                Text("仅记录计时工作与完成的休息，不代表实际用眼时长或健康改善。")
                    .foregroundColor(.secondary)
            }
            Section("关于与隐私") {
                if let url = URL(string: AppSettings.privacyPolicyURLString) { Link("隐私政策", destination: url) }
                if let mail = URL(string: "mailto:\(AppSettings.supportEmail)") { Link("联系支持", destination: mail) }
                Button("重新体验引导") { OnboardingWindowManager.shared.showOnboarding(completion: {}) }
                LabeledContent("版本", value: appVersionString)
            }
            Section {
                Button("恢复默认", role: .destructive) { showResetConfirmation = true }
                    .confirmationDialog("确定要恢复默认设置吗？", isPresented: $showResetConfirmation) {
                        Button("恢复", role: .destructive) { settings.resetToDefaults(); applyLaunchAtLogin(settings.launchAtLogin) }
                        Button("取消", role: .cancel) {}
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 600)
        .onAppear { settings.launchAtLogin = LaunchAtLoginManager.shared.isEnabled() }
        .alert("无法应用系统设置", isPresented: $showSystemError) {
            Button("好", role: .cancel) {}
        } message: { Text(verbatim: systemError) }
    }

    private var smartDetectionSection: some View {
        Section {
            Toggle("启用智能避让", isOn: $settings.enableSmartDetection)
            Group {
                Toggle("会议应用在前台时暂缓提醒", isOn: $settings.detectVideoCall)
                Toggle("演示或媒体应用在前台时暂缓提醒", isOn: $settings.detectFullscreen)
                Toggle("无操作时使用轻提醒", isOn: $settings.detectIdle)
            }
            .disabled(!settings.enableSmartDetection)
        } header: { Text("智能避让") } footer: {
            Text("应用规则依据前台应用判断，不代表已检测到通话或屏幕共享。暂缓提醒时仍累计工作；离开规则应用后留出缓冲再提醒。")
            Text("无操作不等于休息，只改用轻提醒；锁屏或睡眠才暂停工作计时。")
        }
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
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { application, error in
            DispatchQueue.main.async {
                if let error {
                    systemError = error.localizedDescription
                    showSystemError = true
                } else if application != nil { NSApp.terminate(nil) }
            }
        }
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
