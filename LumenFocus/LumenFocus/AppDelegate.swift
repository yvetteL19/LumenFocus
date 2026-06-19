//
//  AppDelegate.swift
//  LumenFocus
//
//  Created by AI Director on 2026/2/4.
//

import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties

    private var menuBarController: MenuBarController?
    private let timerManager = TimerManager.shared
    private let restManager = RestManager.shared

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 隐藏Dock图标（通过Info.plist配置 LSUIElement = YES）
        // 这里作为备用方案，确保应用不显示在Dock
        NSApp.setActivationPolicy(.accessory)

        // 注册诊断订阅（崩溃 / 卡顿数据落本地，可在「设置 → 帮助」导出）
        DiagnosticsManager.shared.register()

        // 调度周报（如果通知已授权）
        WeeklyRecapManager.shared.bootstrap()

        // 预热环境感知（启动时即触发首次评估）
        _ = WorkspaceMonitor.shared

        // 注册全局快捷键 ⌘⌥E = 立即休息
        GlobalShortcutManager.shared.registerImmediateRest()

        // 初始化菜单栏控制器
        menuBarController = MenuBarController()
        menuBarController?.setup()

        // 检查是否首次启动
        let settings = AppSettings.shared
        if !settings.hasCompletedOnboarding {
            showOnboardingWindow()
        } else {
            // 启动定时器
            timerManager.start()
        }

        // 关闭默认窗口
        closeAllWindows()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 停止定时器
        timerManager.stop()

        // 保存当前状态
        let appState = AppState.shared
        appState.saveTodayStatistics() // 确保数据持久化
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 防止点击Dock图标时打开窗口（虽然已经隐藏了Dock图标）
        return false
    }

    // MARK: - Private Methods

    /// 显示首次启动引导窗口
    private func showOnboardingWindow() {
        OnboardingWindowManager.shared.showOnboarding { [weak self] in
            // 引导完成后启动定时器
            self?.timerManager.start()
        }
    }

    /// 关闭所有窗口
    private func closeAllWindows() {
        for window in NSApplication.shared.windows {
            // 保留特殊窗口（如首次引导、设置窗口等）
            if window.title.isEmpty {
                window.close()
            }
        }
    }
}
