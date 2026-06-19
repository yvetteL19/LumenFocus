//
//  SettingsView.swift
//  LumenFocus
//
//  Created by AI Director on 2026/2/4.
//  Updated: 2026/6/19 - Native instant-apply grouped Form (no Save button),
//  full Light/Dark Mode support.
//

import SwiftUI

/// 设置界面 — 原生即时生效（无"保存"按钮），采用分组 Form。
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var showResetConfirmation = false

    // MARK: - Int <-> Double bindings for sliders

    private var workBinding: Binding<Double> {
        Binding(get: { Double(settings.workDurationMinutes) },
                set: { settings.workDurationMinutes = Int($0) })
    }

    private var restBinding: Binding<Double> {
        Binding(get: { Double(settings.restDurationMinutes) },
                set: { settings.restDurationMinutes = Int($0) })
    }

    // MARK: - Body

    var body: some View {
        Form {
            timeConfigSection
            restExperienceSection
            smartDetectionSection
            launchOptionsSection
            statisticsSection
            aboutSection
            resetSection
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 600)
        .onChange(of: settings.launchAtLogin) { newValue in
            DispatchQueue.global(qos: .background).async {
                _ = newValue ? LaunchAtLoginManager.shared.enable()
                             : LaunchAtLoginManager.shared.disable()
            }
        }
    }

    // MARK: - Sections

    private var timeConfigSection: some View {
        Section("时间配置") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("工作时长")
                    Spacer()
                    Text("\(settings.workDurationMinutes) 分钟")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.LumenFocus.textSecondary)
                        .monospacedDigit()
                }
                Slider(value: workBinding, in: 15...120, step: 5)
                    .tint(Color.LumenFocus.ink)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("休息时长")
                    Spacer()
                    Text("\(settings.restDurationMinutes) 分钟")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.LumenFocus.textSecondary)
                        .monospacedDigit()
                }
                Slider(value: restBinding, in: 1...15, step: 1)
                    .tint(Color.LumenFocus.ink)
            }
        }
    }

    private var restExperienceSection: some View {
        Section {
            Picker("环境音", selection: $settings.ambientTrack) {
                ForEach(AmbientTrack.allCases) { t in
                    Text(t.displayName).tag(t)
                }
            }
        } header: {
            Text("休息体验")
        } footer: {
            Text("休息开始时自动播放并循环。默认关闭；可在休息时点菜单栏暂时静音。")
                .font(.system(size: 11))
                .foregroundColor(Color.LumenFocus.textSecondary)
        }
    }

    private var smartDetectionSection: some View {
        Section {
            Toggle("启用智能避让", isOn: $settings.enableSmartDetection)

            Group {
                Toggle(isOn: $settings.detectVideoCall) {
                    Label("视频通话 / 屏幕共享", systemImage: "video.fill")
                }
                Toggle(isOn: $settings.detectFullscreen) {
                    Label("全屏演示 / 视频", systemImage: "rectangle.inset.filled")
                }
                Toggle(isOn: $settings.detectIdle) {
                    Label("长时间无操作（≥ 1 分钟）", systemImage: "moon.zzz")
                }
                Toggle(isOn: $settings.detectScreenLock) {
                    Label("屏幕锁定 / 系统睡眠", systemImage: "lock.fill")
                }
            }
            .disabled(!settings.enableSmartDetection)
        } header: {
            Text("智能避让")
        } footer: {
            Text("当检测到以下场景时自动暂停提醒，避免在错误的时机打扰你。")
                .font(.system(size: 11))
                .foregroundColor(Color.LumenFocus.textSecondary)
        }
    }

    private var launchOptionsSection: some View {
        Section("外观与启动") {
            Toggle("开机时自动启动", isOn: $settings.launchAtLogin)
            Toggle(isOn: $settings.showRemainingMinutesInMenuBar) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("菜单栏显示剩余分钟数字")
                    Text("例如：「眼 23m」。关闭则只显示图标")
                        .font(.system(size: 11))
                        .foregroundColor(Color.LumenFocus.textSecondary)
                }
            }
        }
    }

    private var statisticsSection: some View {
        Section("统计数据") {
            LabeledContent("本周护眼", value: "\(StatisticsManager.shared.getWeeklyRestCount()) 次")
            LabeledContent("本周用眼", value: StatisticsManager.shared.getWeeklyWorkDurationFormatted())
            LabeledContent("平均每天", value: "\(StatisticsManager.shared.getDailyAverageRestCount()) 次")
            Button("查看详细统计") {
                StatisticsWindowManager.shared.show()
            }
        }
    }

    private var aboutSection: some View {
        Section("关于与隐私") {
            if let url = URL(string: AppSettings.privacyPolicyURLString) {
                Link(destination: url) {
                    Label("隐私政策", systemImage: "hand.raised")
                }
            }
            if let mail = URL(string: "mailto:\(AppSettings.supportEmail)") {
                Link(destination: mail) {
                    Label("联系支持", systemImage: "envelope")
                }
            }
            LabeledContent("版本", value: appVersionString)
        }
    }

    private var appVersionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Text("恢复默认")
            }
            .confirmationDialog("确定要恢复默认设置吗？", isPresented: $showResetConfirmation) {
                Button("恢复", role: .destructive) { settings.resetToDefaults() }
                Button("取消", role: .cancel) {}
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
