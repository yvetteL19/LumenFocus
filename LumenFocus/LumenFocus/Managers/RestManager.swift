//
//  RestManager.swift
//  LumenFocus
//
//  Pure rendering layer for rest overlay windows.
//  Subscribes to RestController.stage and creates/destroys NSWindow accordingly.
//  No business state, no race-condition guards — those concerns belong to RestController.
//

import Cocoa
import Combine

/// 休息渲染管理器 — 监听 `RestController.stage` 维护遮罩窗口
final class RestManager {
    static let shared = RestManager()

    // MARK: - Private

    private var overlayWindows: [RestOverlayWindow] = []
    private var countdownTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private let appState = AppState.shared
    private let restController = RestController.shared

    private init() {
        setupSubscriptions()
    }

    // MARK: - Setup

    private func setupSubscriptions() {
        // 阶段变化驱动窗口生命周期
        restController.stage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stage in
                self?.handleStageChange(stage)
            }
            .store(in: &cancellables)

        // 屏幕配置变化（插拔显示器）
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleScreenConfigurationChange()
            }
            .store(in: &cancellables)
    }

    // MARK: - Stage handling

    private func handleStageChange(_ stage: RestStage) {
        switch stage {
        case .idle:
            tearDownWindows()
        case .fadingIn:
            if overlayWindows.isEmpty {
                createOverlayWindows()
                overlayWindows.forEach { $0.fadeIn() }
                startCountdownTimer()
            }
        case .midRest:
            // 主体阶段：窗口保持，M3 在这里嵌入呼吸/远焦点视图
            break
        case .fadingOut:
            overlayWindows.forEach { $0.fadeOut() }
        }
    }

    private func tearDownWindows() {
        stopCountdownTimer()
        let windows = overlayWindows
        overlayWindows.removeAll()
        windows.forEach { window in
            window.stopAllAnimations()
            window.cleanup()
            window.orderOut(nil)
            window.close()
        }
    }

    // MARK: - Window construction

    private func createOverlayWindows() {
        // 防御性清理（理论上 idle → fadingIn 时窗口列表应为空，但热插拔等情况兜底）
        overlayWindows.forEach { $0.close() }
        overlayWindows.removeAll()

        for screen in NSScreen.screens {
            let window = RestOverlayWindow(screen: screen)
            window.orderFrontRegardless()
            overlayWindows.append(window)
        }

        // 关键：菜单栏（accessory）App 必须先激活，遮罩窗口才能成为 key window
        // 接收键盘事件，否则 ESC 收不到、用户被全屏遮罩困住。
        NSApp.activate(ignoringOtherApps: true)
        let keyWindow = overlayWindows.first(where: { $0.screen == NSScreen.main }) ?? overlayWindows.first
        keyWindow?.makeKeyAndOrderFront(nil)
        keyWindow?.makeFirstResponder(keyWindow)
    }

    // MARK: - Countdown

    private func startCountdownTimer() {
        stopCountdownTimer()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateCountdown()
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
        updateCountdown()
    }

    private func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func updateCountdown() {
        let remaining = appState.remainingSeconds
        overlayWindows.forEach { $0.updateCountdown(seconds: remaining) }
    }

    // MARK: - Screen configuration

    private func handleScreenConfigurationChange() {
        // 只有正在休息时才重建（不论 fadingIn / midRest / fadingOut）
        guard restController.stage.value != .idle else { return }

        Log.rest.info("Screen configuration changed; rebuilding overlay windows")

        overlayWindows.forEach { $0.close() }
        overlayWindows.removeAll()

        for screen in NSScreen.screens {
            let window = RestOverlayWindow(screen: screen)
            // 跳过渐变动画，立即显示为暗态
            window.contentView?.subviews.first?.alphaValue = 0.7
            window.orderFrontRegardless()
            overlayWindows.append(window)
            window.updateCountdown(seconds: appState.remainingSeconds)
        }
    }
}
