//
//  AppSettings.swift
//  LumenFocus
//
//  Created by AI Director on 2026/2/4.
//

import Foundation
import Combine

/// 应用设置 - 用户可配置参数
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // MARK: - Published Properties

    /// 工作时长（分钟）- 范围: 15-120分钟，默认40分钟
    @Published var workDurationMinutes: Int {
        didSet {
            UserDefaults.standard.set(workDurationMinutes, forKey: Keys.workDuration)
        }
    }

    /// 休息时长（分钟）- 范围: 1-15分钟，默认5分钟
    @Published var restDurationMinutes: Int {
        didSet {
            UserDefaults.standard.set(restDurationMinutes, forKey: Keys.restDuration)
        }
    }

    /// 是否开机自启动
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin)
        }
    }

    // MARK: - Smart detection (M1)

    /// 智能避让总开关
    @Published var enableSmartDetection: Bool {
        didSet { UserDefaults.standard.set(enableSmartDetection, forKey: Keys.enableSmartDetection) }
    }

    /// 自动避让：长时间无键鼠输入
    @Published var detectIdle: Bool {
        didSet { UserDefaults.standard.set(detectIdle, forKey: Keys.detectIdle); WorkspaceMonitor.shared.enableIdle = detectIdle; WorkspaceMonitor.shared.reevaluate() }
    }

    /// 自动避让：视频通话 / 屏幕共享
    @Published var detectVideoCall: Bool {
        didSet { UserDefaults.standard.set(detectVideoCall, forKey: Keys.detectVideoCall); WorkspaceMonitor.shared.enableVideoCall = detectVideoCall; WorkspaceMonitor.shared.reevaluate() }
    }

    /// 自动避让：全屏应用（演示 / 视频）
    @Published var detectFullscreen: Bool {
        didSet { UserDefaults.standard.set(detectFullscreen, forKey: Keys.detectFullscreen); WorkspaceMonitor.shared.enableFullscreen = detectFullscreen; WorkspaceMonitor.shared.reevaluate() }
    }

    /// 自动避让：屏幕锁定 / 系统睡眠
    @Published var detectScreenLock: Bool {
        didSet { UserDefaults.standard.set(detectScreenLock, forKey: Keys.detectScreenLock); WorkspaceMonitor.shared.enableScreenLock = detectScreenLock; WorkspaceMonitor.shared.reevaluate() }
    }

    // MARK: - Rest experience (M3)

    /// 休息时播放的环境音
    @Published var ambientTrack: AmbientTrack {
        didSet { UserDefaults.standard.set(ambientTrack.rawValue, forKey: Keys.ambientTrack) }
    }

    /// 是否在菜单栏图标旁显示剩余分钟数字
    @Published var showRemainingMinutesInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showRemainingMinutesInMenuBar, forKey: Keys.showRemainingMinutesInMenuBar) }
    }

    // MARK: - Constants

    private enum Keys {
        static let workDuration = "workDurationMinutes"
        static let restDuration = "restDurationMinutes"
        static let launchAtLogin = "launchAtLogin"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"

        static let enableSmartDetection = "enableSmartDetection"
        static let detectIdle = "detectIdle"
        static let detectVideoCall = "detectVideoCall"
        static let detectFullscreen = "detectFullscreen"
        static let detectScreenLock = "detectScreenLock"

        static let ambientTrack = "ambientTrack"
        static let showRemainingMinutesInMenuBar = "showRemainingMinutesInMenuBar"
    }

    /// 默认工作时长（分钟）
    static let defaultWorkDuration = 40

    /// 默认休息时长（分钟）
    static let defaultRestDuration = 5

    // MARK: - App info

    /// 隐私政策页面（GitHub Pages）。
    /// ⚠️ 仓库推送后，请把 `yveluo` 替换为你的实际 GitHub 用户名，并在
    /// 仓库 Settings → Pages 中选择 `main` 分支的 `/docs` 目录发布。
    static let privacyPolicyURLString = "https://yveluo.github.io/LumenFocus/"

    /// 支持邮箱
    static let supportEmail = "yveluo@outlook.com"

    /// 工作时长范围（分钟）
    static let workDurationRange = 15...120

    /// 休息时长范围（分钟）
    static let restDurationRange = 1...15

    // MARK: - Initialization

    private init() {
        self.workDurationMinutes = UserDefaults.standard.object(forKey: Keys.workDuration) as? Int ?? Self.defaultWorkDuration
        self.restDurationMinutes = UserDefaults.standard.object(forKey: Keys.restDuration) as? Int ?? Self.defaultRestDuration
        self.launchAtLogin = UserDefaults.standard.bool(forKey: Keys.launchAtLogin)

        // 智能避让默认全开（首次启动 = 全开）
        self.enableSmartDetection = UserDefaults.standard.object(forKey: Keys.enableSmartDetection) as? Bool ?? true
        self.detectIdle = UserDefaults.standard.object(forKey: Keys.detectIdle) as? Bool ?? true
        self.detectVideoCall = UserDefaults.standard.object(forKey: Keys.detectVideoCall) as? Bool ?? true
        self.detectFullscreen = UserDefaults.standard.object(forKey: Keys.detectFullscreen) as? Bool ?? true
        self.detectScreenLock = UserDefaults.standard.object(forKey: Keys.detectScreenLock) as? Bool ?? true

        // 环境音默认关
        let trackRaw = UserDefaults.standard.string(forKey: Keys.ambientTrack) ?? AmbientTrack.off.rawValue
        self.ambientTrack = AmbientTrack(rawValue: trackRaw) ?? .off

        // 菜单栏剩余分钟数字默认关（保持图标极简）
        self.showRemainingMinutesInMenuBar = UserDefaults.standard.object(forKey: Keys.showRemainingMinutesInMenuBar) as? Bool ?? false
    }

    // MARK: - Public Methods

    /// 是否已完成首次引导
    var hasCompletedOnboarding: Bool {
        get {
            UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.hasCompletedOnboarding)
        }
    }

    /// 重置为默认设置
    func resetToDefaults() {
        workDurationMinutes = Self.defaultWorkDuration
        restDurationMinutes = Self.defaultRestDuration
        launchAtLogin = false
    }

    /// 验证设置有效性
    func validateSettings() -> Bool {
        let workValid = Self.workDurationRange.contains(workDurationMinutes)
        let restValid = Self.restDurationRange.contains(restDurationMinutes)
        return workValid && restValid
    }
}
