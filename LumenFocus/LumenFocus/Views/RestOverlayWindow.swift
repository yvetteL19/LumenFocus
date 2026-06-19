//
//  RestOverlayWindow.swift
//  LumenFocus
//
//  Created by AI Director on 2026/2/4.
//  Design Spec: Based on design_spec.md section 3
//

import Cocoa
import SwiftUI
import Combine

/// 休息遮罩窗口 - 全屏黑色半透明遮罩
class RestOverlayWindow: NSWindow {
    // MARK: - Properties

    private var overlayView: NSView!
    private var countdownLabel: NSTextField!
    private var tipLabel: NSTextField!
    private var escHintLabel: NSTextField!
    private var snoozeButton: NSButton?
    private var snoozeFadeTimer: Timer?

    /// 中段引导视图（主屏专属）— 呼吸 / 远焦点 / 自由切换
    private var midRestHostingView: NSHostingView<AnyView>?
    private var midRestActivityCancellable: AnyCancellable?

    private var currentTip: String = ""

    // MARK: - Initialization

    init(screen: NSScreen) {
        // 创建全屏窗口
        let rect = screen.frame
        super.init(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // 设置屏幕
        self.setFrame(screen.frame, display: true)

        setupWindow()
        setupViews()
    }

    // MARK: - Setup

    private func setupWindow() {
        // 窗口层级：高于所有应用（包括全屏应用）
        self.level = .screenSaver + 1

        // 窗口行为
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // 背景色（初始完全透明）
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false

        // 不接受鼠标事件（但需要捕获键盘事件）
        self.ignoresMouseEvents = false

        // 作为key window以接收键盘事件
        self.makeKeyAndOrderFront(nil)
    }

    private func setupViews() {
        // 创建遮罩视图
        overlayView = NSView(frame: self.frame)
        overlayView.wantsLayer = true
        overlayView.layer?.backgroundColor = NSColor.black.cgColor
        overlayView.alphaValue = 0.0  // 初始透明
        self.contentView?.addSubview(overlayView)

        // 只在主屏幕显示UI元素
        if NSScreen.main == self.screen {
            setupUIElements()
        }
    }

    /// 设置UI元素（倒计时、提示文案、退出提示）
    private func setupUIElements() {
        guard let contentView = self.contentView else { return }
        let frame = contentView.frame

        // 倒计时标签（居中）
        countdownLabel = NSTextField(labelWithString: "5:00")
        countdownLabel.font = NSFont.systemFont(ofSize: 60, weight: .semibold)
        countdownLabel.textColor = .white
        countdownLabel.alignment = .center
        countdownLabel.isBezeled = false
        countdownLabel.drawsBackground = false

        let countdownWidth: CGFloat = 200
        let countdownHeight: CGFloat = 80
        let countdownX = (frame.width - countdownWidth) / 2
        let countdownY = frame.height / 2
        countdownLabel.frame = NSRect(x: countdownX, y: countdownY, width: countdownWidth, height: countdownHeight)

        contentView.addSubview(countdownLabel)

        // 护眼提示文案（倒计时下方32pt）— 按当前时段从 Tips 库挑一条
        currentTip = Tips.random()
        tipLabel = NSTextField(labelWithString: currentTip)
        tipLabel.font = NSFont.systemFont(ofSize: 24, weight: .regular)
        tipLabel.textColor = NSColor.white.withAlphaComponent(0.8)
        tipLabel.alignment = .center
        tipLabel.isBezeled = false
        tipLabel.drawsBackground = false
        tipLabel.maximumNumberOfLines = 2
        tipLabel.lineBreakMode = .byWordWrapping

        let tipWidth: CGFloat = 600
        let tipHeight: CGFloat = 64
        let tipX = (frame.width - tipWidth) / 2
        let tipY = countdownY - 32 - tipHeight
        tipLabel.frame = NSRect(x: tipX, y: tipY, width: tipWidth, height: tipHeight)

        contentView.addSubview(tipLabel)

        // 退出提示（底部40pt）
        escHintLabel = NSTextField(labelWithString: L("按 ESC 提前结束"))
        escHintLabel.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        escHintLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        escHintLabel.alignment = .center
        escHintLabel.isBezeled = false
        escHintLabel.drawsBackground = false

        let escWidth: CGFloat = 200
        let escHeight: CGFloat = 20
        let escX = (frame.width - escWidth) / 2
        let escY: CGFloat = 40
        escHintLabel.frame = NSRect(x: escX, y: escY, width: escWidth, height: escHeight)

        contentView.addSubview(escHintLabel)

        // 「再撑 2 分钟」按钮 — 仅在主屏，渐暗早期可见
        setupSnoozeButton(in: contentView, frame: frame)

        // 中段引导视图：呼吸 / 远焦点 / 自由
        setupMidRestHosting(in: contentView, frame: frame)

        // 设置辅助功能标签
        countdownLabel.setAccessibilityLabel(L("剩余休息时间"))
        tipLabel.setAccessibilityLabel(currentTip)
        escHintLabel.setAccessibilityLabel(L("按Escape键提前结束休息"))
    }

    /// 主屏中段引导视图：根据 RestController.midRestActivity 切换三种 SwiftUI 视图
    private func setupMidRestHosting(in contentView: NSView, frame: NSRect) {
        // 居中铺满，但不覆盖底部 ESC / snooze 区域
        let topInset: CGFloat = countdownLabel.frame.maxY + 24
        let bottomInset: CGFloat = 140
        let hostingFrame = NSRect(
            x: 0,
            y: bottomInset,
            width: frame.width,
            height: frame.height - topInset - bottomInset
        )

        let hosting = NSHostingView(rootView: AnyView(EmptyView()))
        hosting.frame = hostingFrame
        hosting.autoresizingMask = [.width, .height]
        hosting.alphaValue = 0
        contentView.addSubview(hosting)
        midRestHostingView = hosting

        // 订阅 midRest 子活动 — 仅主屏才有 setupUIElements / setupMidRestHosting 调用
        midRestActivityCancellable = RestController.shared.midRestActivity
            .combineLatest(RestController.shared.stage)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] activity, stage in
                self?.handleMidRestUpdate(activity: activity, stage: stage)
            }
    }

    private func handleMidRestUpdate(activity: MidRestActivity, stage: RestStage) {
        guard let hosting = midRestHostingView else { return }

        // 只在 midRest 阶段显示
        guard stage == .midRest else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                hosting.animator().alphaValue = 0
            }
            return
        }

        // 切换 SwiftUI 子视图
        switch activity {
        case .breathing:
            hosting.rootView = AnyView(BreathingCircleView())
            // 进入 midRest 时 tip 文案隐藏，呼吸圆环登场
            tipLabel?.animator().alphaValue = 0
        case .farFocus:
            hosting.rootView = AnyView(FarFocusDotView())
            tipLabel?.animator().alphaValue = 0
        case .free:
            // 自由阶段回到文字 tip — 重新挑一条
            currentTip = Tips.random()
            tipLabel?.stringValue = currentTip
            hosting.rootView = AnyView(EmptyView())
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.6
                tipLabel?.animator().alphaValue = 1
            }
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            hosting.animator().alphaValue = (activity == .free) ? 0 : 1
        }
    }

    private func setupSnoozeButton(in contentView: NSView, frame: NSRect) {
        let button = NSButton(title: L("再撑 2 分钟"), target: self, action: #selector(handleSnoozeClicked))
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        button.contentTintColor = .white
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        button.layer?.cornerRadius = 18
        button.isBordered = false

        let buttonWidth: CGFloat = 130
        let buttonHeight: CGFloat = 36
        let buttonX = (frame.width - buttonWidth) / 2
        // 放在 ESC 提示上方，60pt 间距
        let buttonY = escHintLabel.frame.maxY + 32
        button.frame = NSRect(x: buttonX, y: buttonY, width: buttonWidth, height: buttonHeight)

        button.setAccessibilityLabel(L("再撑 2 分钟后再次提醒"))
        contentView.addSubview(button)
        snoozeButton = button

        // 5 秒后淡出
        let timer = Timer(timeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.fadeOutSnoozeButton()
        }
        RunLoop.main.add(timer, forMode: .common)
        snoozeFadeTimer = timer
    }

    private func fadeOutSnoozeButton() {
        guard let button = snoozeButton else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.6
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            button.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.snoozeButton?.removeFromSuperview()
            self?.snoozeButton = nil
        })
    }

    @objc private func handleSnoozeClicked() {
        Log.rest.info("Snooze button tapped")
        snoozeFadeTimer?.invalidate()
        snoozeFadeTimer = nil
        // 走 TimerManager → RestController.snooze → didFinish(.snoozed) → handleRestFinished
        TimerManager.shared.snoozeCurrentTrigger(by: 120)
    }

    // MARK: - Public Methods

    /// 更新倒计时显示
    /// - Parameter seconds: 剩余秒数
    func updateCountdown(seconds: Int) {
        guard let countdownLabel = countdownLabel else { return }

        let minutes = seconds / 60
        let secs = seconds % 60
        let timeString = String(format: "%d:%02d", minutes, secs)

        DispatchQueue.main.async {
            countdownLabel.stringValue = timeString
            countdownLabel.setAccessibilityLabel(String(format: L("剩余休息时间 %d 分 %d 秒"), minutes, secs))
        }
    }

    /// 开始渐变变暗动画
    /// - Parameters:
    ///   - duration: 渐暗时长。默认 20s，演示模式可传入更短的值
    ///   - completion: 动画结束回调
    func fadeIn(duration: TimeInterval = 20.0, completion: (() -> Void)? = nil) {
        guard let overlayView = overlayView else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            overlayView.animator().alphaValue = 0.7
        }, completionHandler: { [weak self] in
            guard self != nil else { return }
            completion?()
        })
    }

    /// 开始渐变变亮动画
    /// - Parameters:
    ///   - duration: 渐亮时长。默认 20s
    ///   - completion: 动画结束回调
    func fadeOut(duration: TimeInterval = 20.0, completion: (() -> Void)? = nil) {
        guard let overlayView = overlayView else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            overlayView.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            guard self != nil else { return }
            completion?()
        })
    }

    /// 快速退出动画（0.5秒，用于ESC退出）
    func quickFadeOut(completion: (() -> Void)? = nil) {
        guard let overlayView = overlayView else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            overlayView.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            guard self != nil else { return }
            completion?()
        })
    }

    /// 立即停止所有动画
    func stopAllAnimations() {
        // 取消所有进行中的动画，立即设置最终值
        if let overlayView = overlayView {
            overlayView.layer?.removeAllAnimations()
            // 强制结束动画状态
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.0
                context.allowsImplicitAnimation = false
            })
        }
    }

    // MARK: - Keyboard Events

    private var hasHandledEscape = false

    override func keyDown(with event: NSEvent) {
        // 按ESC键退出休息
        if event.keyCode == 53 {  // ESC键的keyCode
            handleEscapeKey()
        } else {
            super.keyDown(with: event)
        }
    }

    private func handleEscapeKey() {
        // 防止多次ESC触发重复处理
        guard !hasHandledEscape else { return }
        hasHandledEscape = true

        // 延迟一拍，让当前 keyDown 事件循环走完再请求关闭窗口，避免在 keyDown 调用栈中触发窗口销毁
        DispatchQueue.main.async {
            RestController.shared.cancelRest()
        }
    }

    // MARK: - Window Delegate

    override var canBecomeKey: Bool {
        return true  // 允许成为key window以接收键盘事件
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    // MARK: - Cleanup

    /// 清理所有UI元素（防止残留）
    func cleanup() {
        // 1. 首先停止所有动画（防止动画回调访问已释放的对象）
        stopAllAnimations()

        // 2. 停止 snooze 淡出计时器
        snoozeFadeTimer?.invalidate()
        snoozeFadeTimer = nil

        // 3. 取消 midRest 订阅
        midRestActivityCancellable?.cancel()
        midRestActivityCancellable = nil

        // 4. 移除所有子视图
        contentView?.subviews.forEach { $0.removeFromSuperview() }

        // 5. 清理引用
        countdownLabel = nil
        tipLabel = nil
        escHintLabel = nil
        snoozeButton = nil
        midRestHostingView = nil
        overlayView = nil

        // 6. 重置ESC标志（允许下次休息时重新使用）
        hasHandledEscape = false
    }
}
