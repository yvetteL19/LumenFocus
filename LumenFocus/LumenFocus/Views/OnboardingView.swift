import SwiftUI

/// Presets state exactly the durations that will be applied.
enum CadencePreset: Hashable, CaseIterable {
    case strict, `default`, deepWork, custom
    var title: String {
        switch self {
        case .strict: return "短暂离屏"
        case .default: return "规律休息"
        case .deepWork: return "较长间隔"
        case .custom: return "自定义"
        }
    }
    var subtitle: String {
        switch self {
        case .strict: return "每 20 分钟，休息 20 秒"
        case .default: return "每 40 分钟，休息 5 分钟"
        case .deepWork: return "每 50 分钟，休息 10 分钟"
        case .custom: return "自己设定"
        }
    }
    var work: Int {
        switch self { case .strict: return 20; case .default: return 40; case .deepWork: return 50; case .custom: return 20 }
    }
    var rest: Int {
        switch self { case .strict: return 20; case .default: return 300; case .deepWork: return 600; case .custom: return 20 }
    }
}

struct OnboardingView: View {
    @State private var step = 1
    @State private var selectedPreset: CadencePreset = .strict
    @State private var customWork = 20.0
    @State private var customRest = 20
    @State private var reminderMode: ReminderMode = .gentle
    @State private var launchAtLogin = false
    @State private var isPlayingDemo = false
    @State private var launchError = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: String(format: L("第 %d 步，共 4 步"), step))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Button("使用当前设置开始") { OnboardingWindowManager.shared.close() }
                    .buttonStyle(.borderless)
                    .disabled(isPlayingDemo)
            }
            .padding(24)
            Divider()
            // Only the content scrolls. Navigation always remains reachable, including
            // English copy and the expanded custom cadence on smaller displays.
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch step {
                    case 1: welcome
                    case 2: demo
                    case 3: cadence
                    default: options
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28)
            }
            Divider()
            HStack {
                if step > 1 { Button("上一步") { step -= 1 } }
                Spacer()
                Button {
                    if step < 4 { step += 1 } else { completeOnboarding() }
                } label: {
                    Text(verbatim: L(step == 4 ? "开始提醒" : "继续"))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color.LumenFocus.ink)
            }
            .disabled(isPlayingDemo)
            .padding(24)
        }
        .frame(minWidth: 460, minHeight: 440)
        .background(Color.LumenFocus.backgroundPrimary)
        .onAppear {
            let settings = AppSettings.shared
            customWork = Double(settings.workDurationMinutes)
            customRest = settings.restDurationSeconds
            selectedPreset = CadencePreset.allCases.first(where: { $0 != .custom && $0.work == settings.workDurationMinutes && $0.rest == settings.restDurationSeconds }) ?? .custom
            reminderMode = settings.reminderMode
            launchAtLogin = LaunchAtLoginManager.shared.isEnabled()
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("给工作留一点离屏时间")
                .font(.system(size: 27, weight: .medium))
            feature("eye", "到点轻轻提醒，由你决定何时开始休息")
            feature("hand.raised", "随时延后、暂停或结束，不会困住你")
            feature("internaldrive", "工作与休息记录保存在这台 Mac 上")
            Text("完成设置后，你可以从屏幕顶部的菜单栏找到 LumenFocus。")
                .foregroundColor(.secondary)
        }
    }

    private var demo: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("先体验一下（可选）").font(.system(size: 25, weight: .medium))
            Text("轻提醒不会遮挡工作。主动开始休息后，屏幕会渐暗，提醒你看向屏幕之外。")
            Text("这个 10 秒演示只显示在当前屏幕；正式休息覆盖所有屏幕，每块屏幕都有结束按钮。")
                .foregroundColor(.secondary)
            Button {
                isPlayingDemo = true
                OnboardingDemo.shared.play(totalDuration: 10) { isPlayingDemo = false }
            } label: {
                Label { Text(verbatim: L(isPlayingDemo ? "演示中…" : "体验 10 秒演示")) } icon: { Image(systemName: "play.circle") }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.LumenFocus.ink)
            .disabled(isPlayingDemo)
            Text("演示中可按 Esc 或点击结束。不计入休息记录；也可直接继续。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    private var cadence: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("选择你的节奏").font(.system(size: 25, weight: .medium))
            ForEach(CadencePreset.allCases, id: \.self) { preset in
                Button { selectedPreset = preset } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selectedPreset == preset ? "checkmark.circle.fill" : "circle")
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: L(preset.title)).font(.system(size: 15, weight: .medium))
                            Text(verbatim: L(preset.subtitle)).font(.system(size: 12)).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(13)
                    .contentShape(Rectangle())
                    .background(selectedPreset == preset ? Color.LumenFocus.backgroundSecondary : .clear)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.LumenFocus.border))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedPreset == preset ? .isSelected : [])
            }
            if selectedPreset == .custom {
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: String(format: L("工作 %d 分钟"), Int(customWork)))
                    Slider(value: $customWork, in: 15...120, step: 5)
                        .tint(Color.LumenFocus.ink)
                        .accessibilityLabel(Text("工作时长"))
                        .accessibilityValue(Text(verbatim: String(format: L("%d 分钟"), Int(customWork))))
                    Picker("休息时长", selection: $customRest) {
                        ForEach(restDurationChoices(including: customRest), id: \.self) { seconds in
                            Text(verbatim: restDurationText(seconds)).tag(seconds)
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("让提醒适合你的工作").font(.system(size: 25, weight: .medium))
            Picker("提醒方式", selection: $reminderMode) {
                ForEach(ReminderMode.allCases) { mode in Text(verbatim: mode.displayName).tag(mode) }
            }
            Text(verbatim: L(reminderMode == .gentle ? "到点显示轻提醒。你点击开始后，才会进入离屏休息。" : "到点自动渐暗所有屏幕。休息全程可结束或延后。"))
                .foregroundColor(.secondary)
            Toggle("开机时自动启动", isOn: $launchAtLogin)
            Text("你可以稍后在设置中更改。无需通知权限，也能收到休息提醒。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            if launchError {
                Text("系统未能应用开机启动设置。请在系统设置的登录项中检查；当前状态未被更改。")
                    .foregroundColor(.secondary)
                Button("继续并稍后设置") { finishOnboarding() }
            }
        }
    }

    private func feature(_ symbol: String, _ key: String) -> some View {
        Label { Text(verbatim: L(key)).fixedSize(horizontal: false, vertical: true) } icon: {
            Image(systemName: symbol).frame(width: 24).foregroundColor(Color.LumenFocus.ink)
        }
    }

    private func completeOnboarding() {
        let manager = LaunchAtLoginManager.shared
        if manager.isEnabled() != launchAtLogin {
            let success = launchAtLogin ? manager.enable() : manager.disable()
            guard success, manager.isEnabled() == launchAtLogin else { launchError = true; return }
        }
        finishOnboarding()
    }

    private func finishOnboarding() {
        let settings = AppSettings.shared
        settings.workDurationMinutes = selectedPreset == .custom ? Int(customWork) : selectedPreset.work
        settings.restDurationSeconds = selectedPreset == .custom ? customRest : selectedPreset.rest
        settings.reminderMode = reminderMode
        settings.launchAtLogin = LaunchAtLoginManager.shared.isEnabled()
        settings.hasCompletedOnboarding = true
        OnboardingWindowManager.shared.close()
    }
}

func restDurationChoices(including current: Int) -> [Int] {
    Array(Set([20, 30, 60, 120, 300, 600, 900, current])).sorted()
}

func restDurationText(_ seconds: Int) -> String {
    if seconds % 60 == 0 { return String(format: L("%d 分钟"), seconds / 60) }
    return String(format: L("%d 秒"), seconds)
}
