import Cocoa

/// Full-screen presentation only. All lifecycle decisions belong to RestController.
final class RestOverlayWindow: NSWindow {
    var isPrimaryDisplay: Bool {
        didSet { headingLabel?.font = .systemFont(ofSize: isPrimaryDisplay ? 30 : 25, weight: .medium) }
    }
    private var dimView: NSView!
    private var headingLabel: NSTextField!
    private var countdownLabel: NSTextField!
    private var hasSubmittedAction = false
    private var isCleanedUp = false
    private let reduceMotion: () -> Bool
    private let onEnd: () -> Void
    private let onPostpone: () -> Void

    /// Injectable point geometry and actions let tests inspect an unordered window
    /// without adding displays, changing accessibility preferences or starting a timer.
    init(screenFrame: CGRect, isPrimaryDisplay: Bool = true,
         reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
         onEnd: @escaping () -> Void = { RestController.shared.cancelRest() },
         onPostpone: @escaping () -> Void = { RestController.shared.snooze(by: ReminderPresentation.defaultSnoozeSeconds) }) {
        self.isPrimaryDisplay = isPrimaryDisplay
        self.reduceMotion = reduceMotion
        self.onEnd = onEnd
        self.onPostpone = onPostpone
        super.init(contentRect: screenFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(screenFrame, display: true)
        title = L("离屏休息")
        setAccessibilityLabel(title)
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
        dimView = NSView(frame: DisplayLayout.contentBounds(for: content.bounds))
        dimView.identifier = NSUserInterfaceItemIdentifier("rest.dim")
        dimView.autoresizingMask = [.width, .height]
        dimView.wantsLayer = true
        dimView.layer?.backgroundColor = NSColor.black.cgColor
        dimView.alphaValue = 0
        content.addSubview(dimView)

        headingLabel = label(L("看向屏幕之外"), size: isPrimaryDisplay ? 30 : 25, weight: .medium)
        headingLabel.identifier = NSUserInterfaceItemIdentifier("rest.heading")
        let instruction = label(L("看向窗外或房间远处，自然眨眼。"), size: 19)
        instruction.maximumNumberOfLines = 0
        instruction.lineBreakMode = .byWordWrapping
        countdownLabel = label("", size: 17)
        countdownLabel.identifier = NSUserInterfaceItemIdentifier("rest.countdown")
        countdownLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .regular)
        countdownLabel.textColor = NSColor.white.withAlphaComponent(0.75)

        let end = NSButton(title: L("提前结束"), target: self, action: #selector(endRest))
        end.bezelStyle = .rounded
        end.keyEquivalent = "\u{1b}"
        end.keyEquivalentModifierMask = []
        end.identifier = NSUserInterfaceItemIdentifier("rest.end")
        end.setAccessibilityIdentifier("rest.end")
        end.setAccessibilityHelp(L("提前结束不会计入完成次数。"))
        let postpone = NSButton(title: ReminderPresentation.defaultSnoozeTitle(), target: self, action: #selector(postponeRest))
        postpone.bezelStyle = .rounded
        postpone.identifier = NSUserInterfaceItemIdentifier("rest.postpone")
        postpone.setAccessibilityIdentifier("rest.postpone")
        end.nextKeyView = postpone
        postpone.nextKeyView = end
        let controls = NSStackView(views: [end, postpone])
        controls.orientation = .horizontal
        controls.spacing = 12
        controls.distribution = .fillEqually
        let hint = label(L("随时可提前结束 · Esc"), size: 13)
        let stack = NSStackView(views: [headingLabel, instruction, countdownLabel, controls, hint])
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

    func showDimmed() { dimView?.alphaValue = 0.85 }

    private func animateDim(to alpha: CGFloat, duration: TimeInterval, completion: (() -> Void)?) {
        guard let dimView else { completion?(); return }
        if reduceMotion() {
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
        submit(onEnd)
    }

    @objc private func postponeRest() {
        submit(onPostpone)
    }

    private func submit(_ action: @escaping () -> Void) {
        guard !hasSubmittedAction, !isCleanedUp else { return }
        hasSubmittedAction = true
        // Closing an overlay is deferred beyond its button/key event. A screen
        // removal or interrupted session invalidates callbacks from that window.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isCleanedUp else { return }
            action()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { endRest() } else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) { endRest() }
    override var canBecomeKey: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func stopAllAnimations() { dimView?.layer?.removeAllAnimations() }
    func cleanup() {
        isCleanedUp = true
        stopAllAnimations()
        contentView?.subviews.forEach { $0.removeFromSuperview() }
        dimView = nil
        headingLabel = nil
        countdownLabel = nil
    }
}
