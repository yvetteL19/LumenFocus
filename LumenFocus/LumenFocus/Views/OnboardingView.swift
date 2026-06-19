//
//  OnboardingView.swift
//  LumenFocus
//
//  Four-step onboarding flow:
//    1. Welcome
//    2. Try the gradual dimming (10s demo)
//    3. Choose your rhythm (presets + custom)
//    4. Launch options + notification permission
//

import SwiftUI
import UserNotifications

/// 节奏预设
enum CadencePreset: Hashable {
    /// 严格 20-20-20 法则
    case strict
    /// 默认 40 / 5 — 推荐
    case `default`
    /// 深度工作 50 / 10
    case deepWork
    /// 自定义
    case custom

    var title: String {
        switch self {
        case .strict:   return "20-20-20"
        case .default:  return "默认"
        case .deepWork: return "深度工作"
        case .custom:   return "自定义"
        }
    }

    var subtitle: String {
        switch self {
        case .strict:   return "20 分钟 / 20 秒（医学共识）"
        case .default:  return "40 分钟 / 5 分钟"
        case .deepWork: return "50 分钟 / 10 分钟"
        case .custom:   return "自己设定"
        }
    }

    var work: Int {
        switch self {
        case .strict:   return 20
        case .default:  return 40
        case .deepWork: return 50
        case .custom:   return AppSettings.shared.workDurationMinutes
        }
    }

    var rest: Int {
        switch self {
        case .strict:   return 1     // 1 分钟（最低值；严格 20-20-20 其实是 20 秒，但 AppSettings 最小 1 分钟）
        case .default:  return 5
        case .deepWork: return 10
        case .custom:   return AppSettings.shared.restDurationMinutes
        }
    }
}

struct OnboardingView: View {
    @State private var step: Int = 1
    @State private var selectedPreset: CadencePreset = .default
    @State private var customWork: Double = 40
    @State private var customRest: Double = 5
    @State private var launchAtLogin: Bool = true
    @State private var isPlayingDemo = false

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            // 步骤指示器
            stepIndicator
                .padding(.top, 24)
                .padding(.bottom, 12)

            // 主要内容
            Group {
                switch step {
                case 1: stepWelcome
                case 2: stepDemo
                case 3: stepPreset
                default: stepPermissions
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 32)

            // 底部导航
            navigationBar
                .padding(24)
        }
        .frame(width: 520, height: 480)
        .background(Color.LumenFocus.backgroundPrimary)
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(1...totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Color.LumenFocus.ink : Color.LumenFocus.textTertiary)
                    .frame(width: i == step ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: step)
            }
        }
    }

    // MARK: - Step 1: Welcome

    private var stepWelcome: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("欢迎使用 LumenFocus")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Color.LumenFocus.textPrimary)

            VStack(spacing: 16) {
                FeatureRow(systemImage: "eye.fill", text: "屏幕缓慢渐暗代替闹钟，温柔提醒护眼")
                FeatureRow(systemImage: "wand.and.stars", text: "视频会议、演示、离开时自动避让")
                FeatureRow(systemImage: "chart.bar.fill", text: "本地记录用眼数据，无任何上传")
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Color.LumenFocus.backgroundSecondary)
            .cornerRadius(8)
            Spacer()
        }
    }

    // MARK: - Step 2: Demo

    private var stepDemo: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("先感受一下")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(Color.LumenFocus.textPrimary)

            Text("到了该休息的时刻，LumenFocus 会用 20 秒让屏幕缓慢暗下来。\n点下面试 10 秒压缩版。")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundColor(Color.LumenFocus.textSecondary)
                .lineSpacing(4)

            Button(action: playDemo) {
                HStack(spacing: 8) {
                    Image(systemName: isPlayingDemo ? "hourglass" : "play.circle.fill")
                    Text(isPlayingDemo ? "演示中…" : "亲身感受一下（10 秒）")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(Color.LumenFocus.onInk)
                .frame(width: 240, height: 48)
                .background(Color.LumenFocus.ink)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(isPlayingDemo)
            .opacity(isPlayingDemo ? 0.6 : 1)

            Text("演示会用与正式休息相同的渐暗效果，但不计入今日统计。")
                .font(.system(size: 12))
                .foregroundColor(Color.LumenFocus.textTertiary)
                .padding(.top, 4)
            Spacer()
        }
    }

    // MARK: - Step 3: Preset

    private var stepPreset: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 8)
            Text("选择你的节奏")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color.LumenFocus.textPrimary)

            VStack(spacing: 10) {
                presetCard(.default)
                presetCard(.strict)
                presetCard(.deepWork)
                presetCard(.custom)
            }

            if selectedPreset == .custom {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("工作 \(Int(customWork)) 分钟")
                            .font(.system(size: 13))
                            .foregroundColor(Color.LumenFocus.textSecondary)
                        Slider(value: $customWork, in: 15...120, step: 5)
                            .accentColor(Color.LumenFocus.ink)
                    }
                    HStack {
                        Text("休息 \(Int(customRest)) 分钟")
                            .font(.system(size: 13))
                            .foregroundColor(Color.LumenFocus.textSecondary)
                        Slider(value: $customRest, in: 1...15, step: 1)
                            .accentColor(Color.LumenFocus.ink)
                    }
                }
                .padding(12)
                .background(Color.LumenFocus.backgroundSecondary)
                .cornerRadius(8)
            }
            Spacer()
        }
    }

    private func presetCard(_ preset: CadencePreset) -> some View {
        let selected = (selectedPreset == preset)
        return Button(action: { selectedPreset = preset }) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(selected ? Color.LumenFocus.ink : Color.LumenFocus.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(preset.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color.LumenFocus.textPrimary)
                        if preset == .default {
                            Text("推荐")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color.LumenFocus.onInk)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.LumenFocus.ink)
                                .cornerRadius(4)
                        }
                    }
                    Text(preset.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Color.LumenFocus.textSecondary)
                }
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(selected ? Color.LumenFocus.backgroundSecondary : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.LumenFocus.ink : Color.LumenFocus.border, lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 4: Permissions

    private var stepPermissions: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("最后一步")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color.LumenFocus.textPrimary)

            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $launchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("开机时自动启动")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color.LumenFocus.textPrimary)
                        Text("每次开机自动在菜单栏待命")
                            .font(.system(size: 12))
                            .foregroundColor(Color.LumenFocus.textSecondary)
                    }
                }
                .toggleStyle(.switch)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.fill")
                            .foregroundColor(Color.LumenFocus.gray800)
                        Text("通知权限")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color.LumenFocus.textPrimary)
                    }
                    Text("用于每周日 20:00 发送护眼周报。完全本地生成，不会推送任何广告。")
                        .font(.system(size: 12))
                        .foregroundColor(Color.LumenFocus.textSecondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.LumenFocus.backgroundSecondary)
            .cornerRadius(8)
            Spacer()
        }
    }

    // MARK: - Navigation

    private var navigationBar: some View {
        HStack {
            if step > 1 {
                Button("上一步") { step -= 1 }
                    .buttonStyle(.plain)
                    .foregroundColor(Color.LumenFocus.textSecondary)
            }
            Spacer()
            Button(action: handlePrimary) {
                Text(primaryButtonTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.LumenFocus.onInk)
                    .frame(minWidth: 140, minHeight: 36)
                    .padding(.horizontal, 16)
                    .background(Color.LumenFocus.ink)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(isPlayingDemo)
            .opacity(isPlayingDemo ? 0.5 : 1)
        }
    }

    private var primaryButtonTitle: String {
        step == totalSteps ? "开始守护我的眼睛" : "继续"
    }

    private func handlePrimary() {
        if step < totalSteps {
            step += 1
        } else {
            completeOnboarding()
        }
    }

    // MARK: - Actions

    private func playDemo() {
        guard !isPlayingDemo else { return }
        isPlayingDemo = true
        OnboardingDemo.shared.play(totalDuration: 10) {
            isPlayingDemo = false
        }
    }

    private func completeOnboarding() {
        // 1. 应用预设到 AppSettings
        let settings = AppSettings.shared
        if selectedPreset == .custom {
            settings.workDurationMinutes = Int(customWork)
            settings.restDurationMinutes = Int(customRest)
        } else {
            settings.workDurationMinutes = selectedPreset.work
            settings.restDurationMinutes = selectedPreset.rest
        }
        settings.launchAtLogin = launchAtLogin
        settings.hasCompletedOnboarding = true

        // 2. 后台处理开机自启
        if launchAtLogin {
            DispatchQueue.global(qos: .background).async {
                _ = LaunchAtLoginManager.shared.enable()
            }
        }

        // 3. 请求通知权限（弱失败：用户拒绝也不影响主流程）
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge]) { granted, error in
            if let error {
                Log.notifications.error("Notification auth error: \(error.localizedDescription, privacy: .public)")
            } else {
                Log.notifications.info("Notification authorization granted=\(granted)")
            }
        }

        // 4. 关闭引导窗口
        OnboardingWindowManager.shared.close()
    }

    // MARK: - Subviews

    struct FeatureRow: View {
        let systemImage: String
        let text: String

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                    .foregroundColor(Color.LumenFocus.gray800)
                    .frame(width: 24, alignment: .leading)
                Text(text)
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .foregroundColor(Color.LumenFocus.textPrimary)
                Spacer()
            }
        }
    }
}

#Preview {
    OnboardingView()
}
