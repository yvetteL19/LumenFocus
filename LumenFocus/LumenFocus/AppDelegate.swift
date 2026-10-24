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
    private lazy var timerManager = TimerManager.shared
    private lazy var restManager = RestManager.shared
    private var relaunchHandoff: RelaunchHandoff?
    private var runtimeDidStart = false
    private var showGeneralAfterRelaunch = false

    private var isTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hosted unit tests must never initialize production timers or preferences.
        guard !isTestHost else { return }
        let current = NSRunningApplication.current
        if let launchDate = current.launchDate, let bundleID = Bundle.main.bundleIdentifier,
           let intent = RelaunchIntentStore.shared.consume(currentPID: current.processIdentifier,
                                                           currentLaunchDate: launchDate,
                                                           bundleIdentifier: bundleID) {
            if let previous = NSRunningApplication(processIdentifier: intent.previousPID) {
                // Validate the original process, not a later reuse of its PID.
                if intent.matchesPredecessor(bundleIdentifier: previous.bundleIdentifier,
                                             launchDate: previous.launchDate) {
                    showGeneralAfterRelaunch = true
                    waitForPredecessor(previous)
                    return
                }
            } else {
                // The original instance may already have completed its final flush.
                showGeneralAfterRelaunch = true
            }
        }
        // Keep explicit command-line entry points useful for development launches.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--relaunch-after-pid"), index + 1 < arguments.count,
           let previousPID = Int32(arguments[index + 1]), previousPID > 0,
           previousPID != ProcessInfo.processInfo.processIdentifier,
           let previous = NSRunningApplication(processIdentifier: previousPID),
           previous.bundleIdentifier == Bundle.main.bundleIdentifier {
            waitForPredecessor(previous)
            return
        }
        startRuntime()
    }

    private func waitForPredecessor(_ previous: NSRunningApplication) {
        let handoff = RelaunchHandoff(isRunning: { _ in !previous.isTerminated })
        relaunchHandoff = handoff
        handoff.wait(for: previous.processIdentifier) { [weak self] in self?.startRuntime() }
        // Return immediately so the caller's launch completion can terminate the
        // predecessor, flush its records and release its global shortcut.
    }

    private func startRuntime() {
        guard !runtimeDidStart else { return }
        runtimeDidStart = true
        relaunchHandoff = nil
        // 隐藏Dock图标（通过Info.plist配置 LSUIElement = YES）
        // 这里作为备用方案，确保应用不显示在Dock
        NSApp.setActivationPolicy(.accessory)

        _ = restManager

        // 注册诊断订阅（崩溃 / 卡顿数据仅落本地）
        DiagnosticsManager.shared.register()

        // 清除旧版本包含过期快照的重复周报
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

        if settings.hasCompletedOnboarding,
           showGeneralAfterRelaunch || ProcessInfo.processInfo.arguments.contains("--show-settings-general") {
            SettingsWindowManager.shared.showSettings(initiallyShowGeneral: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !isTestHost, runtimeDidStart else { return }
        // 停止定时器
        timerManager.stop()

        // 保存当前状态
        let appState = AppState.shared
        appState.saveTodayStatistics() // 确保数据持久化
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !isTestHost, runtimeDidStart else { return false }
        // Opening the app again should reveal its controls, even without a Dock window.
        if !AppSettings.shared.hasCompletedOnboarding {
            showOnboardingWindow()
        } else if !flag {
            menuBarController?.showPopover()
        }
        return false
    }

    func showSettings() {
        guard runtimeDidStart else { return }
        SettingsWindowManager.shared.showSettings()
    }

    func showReminders() {
        guard runtimeDidStart else { return }
        menuBarController?.showPopover()
    }

    func showStatistics() {
        guard runtimeDidStart else { return }
        StatisticsWindowManager.shared.show()
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
