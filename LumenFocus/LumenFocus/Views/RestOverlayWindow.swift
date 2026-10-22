import Cocoa

/// Full-screen presentation only. All lifecycle decisions belong to RestController.
final class RestOverlayWindow: NSWindow {
    let isPrimaryDisplay: Bool
    private var dimView: NSView!
    private var countdownLabel: NSTextField!
    private var hasHandledEscape = false

    init(screen: NSScreen, isPrimaryDisplay: Bool = true) {
        self.isPrimaryDisplay = isPrimaryDisplay
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(screen.frame, display: true)
        level = .screenSaver + 1
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        setupContent()
    }

    private func setupContent() {
        guard let content = contentView else { return }
        // Screen frames are global; child views must use the window's local bounds.
        dimView = NSView(frame: content.bounds)
        dimView.autoresizingMask = [.width, .height]
        dimView.wantsLayer = true
        dimView.layer?.backgroundColor = NSColor.black.cgColor
        dimView.alphaValue = 0
        content.addSubview(dimView)

        let heading = label(L("看向屏幕之外"), size: isPrimaryDisplay ? 30 : 25, weight: .medium)
        let instruction = label(L("找一个远处的物体，轻松眨眼。"), size: 17)
        instruction.maximumNumberOfLines = 0
        instruction.lineBreakMode = .byWordWrapping
        countdownLabel = label("", size: 42, weight: .medium)
        countdownLabel.font = .monospacedDigitSystemFont(ofSize: 42, weight: .medium)

        let end = NSButton(title: L("结束休息"), target: self, action: #selector(endRest))
        end.bezelStyle = .rounded
        end.keyEquivalent = "\u{1b}"
        end.setAccessibilityHelp(L("按Escape键提前结束休息"))
        let postpone = NSButton(title: L("2 分钟后再提醒"), target: self, action: #selector(postponeRest))
        postpone.bezelStyle = .rounded
        let controls = NSStackView(views: [end, postpone])
        controls.orientation = .horizontal
        controls.spacing = 12
        controls.distribution = .fillEqually
        let hint = label(L("随时可结束 · Esc"), size: 13)
        let stack = NSStackView(views: [heading, instruction, countdownLabel, controls, hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 22
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            instruction.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -48),
            controls.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
        ])
        initialFirstResponder = end
        // Buttons remain present on every display throughout all rest stages.
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = .white
        label.alignment = .center
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateCountdown(seconds: Int) {
        let seconds = max(0, seconds)
        countdownLabel?.stringValue = String(format: "%d:%02d", seconds / 60, seconds % 60)
        countdownLabel?.setAccessibilityLabel(String(format: L("剩余休息时间 %d 分 %d 秒"), seconds / 60, seconds % 60))
    }

    func fadeIn(duration: TimeInterval = RestController.fadeInDuration, completion: (() -> Void)? = nil) {
        animateDim(to: 0.85, duration: duration, completion: completion)
    }

    func fadeOut(duration: TimeInterval = RestController.fadeOutDuration, completion: (() -> Void)? = nil) {
        animateDim(to: 0, duration: duration, completion: completion)
    }

    func showDimmed() { dimView.alphaValue = 0.85 }

    private func animateDim(to alpha: CGFloat, duration: TimeInterval, completion: (() -> Void)?) {
        guard let dimView else { completion?(); return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            dimView.alphaValue = alpha
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dimView.animator().alphaValue = alpha
        }, completionHandler: completion)
    }

    @objc private func endRest() {
        guard !hasHandledEscape else { return }
        hasHandledEscape = true
        DispatchQueue.main.async { RestController.shared.cancelRest() }
    }

    @objc private func postponeRest() {
        DispatchQueue.main.async { RestController.shared.snooze(by: 120) }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { endRest() } else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) { endRest() }
    override var canBecomeKey: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func stopAllAnimations() { dimView?.layer?.removeAllAnimations() }
    func cleanup() {
        stopAllAnimations()
        contentView?.subviews.forEach { $0.removeFromSuperview() }
        dimView = nil
        countdownLabel = nil
    }
}
