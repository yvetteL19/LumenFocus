//
//  OnboardingWindowManager.swift
//  LumenFocus
//
//  Created by AI Director on 2026/2/4.
//

import Cocoa
import SwiftUI

/// 首次启动引导窗口管理器
class OnboardingWindowManager: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowManager()

    private var onboardingWindow: NSWindow?
    private var hostingController: NSHostingController<OnboardingView>?
    private var completion: (() -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - Public Methods

    /// 显示首次启动引导
    func showOnboarding(allowClose: Bool = false, completion: @escaping () -> Void) {
        self.completion = completion

        if let window = onboardingWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let onboardingView = OnboardingView()
        let controller = NSHostingController(rootView: onboardingView)
        hostingController = controller

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = L("欢迎")
        window.contentViewController = controller
        window.center()
        // .normal（而非 .floating）：避免引导窗压在系统通知授权弹窗之上导致"卡住"
        window.level = .normal
        window.styleMask.remove(.resizable)

        if !allowClose {
            window.styleMask.remove(.closable)
        }

        window.isRestorable = false
        window.delegate = self

        onboardingWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 关闭引导窗口
    func close() {
        guard let window = onboardingWindow else { return }
        window.close()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        let savedCompletion = completion

        // 清理引用
        onboardingWindow = nil
        hostingController = nil
        completion = nil

        // 延迟调用完成回调（确保窗口完全关闭后）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            savedCompletion?()
        }
    }
}
