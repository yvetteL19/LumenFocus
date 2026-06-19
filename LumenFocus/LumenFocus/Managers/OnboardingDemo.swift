//
//  OnboardingDemo.swift
//  LumenFocus
//
//  Plays a 10-second compressed version of the gradual dimming so first-time
//  users see what they're signing up for. Uses a dedicated, self-contained
//  overlay (NOT the production RestOverlayWindow) so it is always dismissable
//  via ESC or a click and never couples to RestController state.
//

import Cocoa

/// Onboarding 渐暗体验演示
final class OnboardingDemo {
    static let shared = OnboardingDemo()

    private var window: DemoOverlayWindow?
    private var fadeOutTimer: Timer?
    private var teardownTimer: Timer?
    private var isRunning = false
    private var completionHandler: (() -> Void)?

    private init() {}

    /// 在主屏上跑一遍压缩版：30% 渐暗 → 40% 暗态 → 30% 渐亮。
    /// 任意时刻按 ESC 或点击都会立即结束。
    func play(totalDuration: TimeInterval = 10, completion: (() -> Void)? = nil) {
        guard !isRunning else {
            Log.rest.warning("OnboardingDemo.play called while already running; ignored")
            return
        }
        guard let main = NSScreen.main else {
            completion?()
            return
        }

        Log.rest.info("OnboardingDemo started (total=\(totalDuration, format: .fixed(precision: 0))s)")
        isRunning = true
        completionHandler = completion

        let overlay = DemoOverlayWindow(screen: main)
        overlay.onDismiss = { [weak self] in self?.teardown() }
        overlay.makeKeyAndOrderFront(nil)
        window = overlay

        let fadeIn = totalDuration * 0.3
        let mid = totalDuration * 0.4

        overlay.fade(to: 0.7, duration: fadeIn)

        let toFadeOut = Timer(timeInterval: fadeIn + mid, repeats: false) { [weak self] _ in
            self?.window?.fade(to: 0.0, duration: totalDuration * 0.3)
        }
        RunLoop.main.add(toFadeOut, forMode: .common)
        fadeOutTimer = toFadeOut

        let toTeardown = Timer(timeInterval: totalDuration + 0.2, repeats: false) { [weak self] _ in
            self?.teardown()
        }
        RunLoop.main.add(toTeardown, forMode: .common)
        teardownTimer = toTeardown
    }

    /// 立即取消演示
    func cancel() { teardown() }

    private func teardown() {
        guard isRunning else { return }
        Log.rest.info("OnboardingDemo teardown")
        fadeOutTimer?.invalidate()
        teardownTimer?.invalidate()
        fadeOutTimer = nil
        teardownTimer = nil

        window?.orderOut(nil)
        window?.close()
        window = nil
        isRunning = false

        let completion = completionHandler
        completionHandler = nil
        DispatchQueue.main.async { completion?() }
    }
}

// MARK: - Dedicated demo overlay

/// 仅供 Onboarding 演示使用的轻量遮罩窗口：黑色半透明 + 一行提示，
/// ESC / 点击 / 计时器任一都能结束。不订阅 RestController，无残留风险。
private final class DemoOverlayWindow: NSWindow {
    var onDismiss: (() -> Void)?
    private let dimView = NSView()

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(screen.frame, display: true)
        level = .screenSaver + 1
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false

        guard let content = contentView else { return }
        dimView.frame = content.bounds
        dimView.autoresizingMask = [.width, .height]
        dimView.wantsLayer = true
        dimView.layer?.backgroundColor = NSColor.black.cgColor
        dimView.alphaValue = 0
        content.addSubview(dimView)

        let label = NSTextField(labelWithString: L("演示中 · 按 ESC 或点击结束"))
        label.font = .systemFont(ofSize: 18, weight: .regular)
        label.textColor = NSColor.white.withAlphaComponent(0.85)
        label.alignment = .center
        label.isBezeled = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor)
        ])
    }

    func fade(to alpha: CGFloat, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dimView.animator().alphaValue = alpha
        }
    }

    override var canBecomeKey: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onDismiss?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onDismiss?()
    }
}
