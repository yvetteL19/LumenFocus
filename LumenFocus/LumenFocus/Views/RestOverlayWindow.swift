import Cocoa

/// A non-activating visual layer. It never pauses applications or changes media playback.
/// The first key dismisses the layer; it is consumed here and never replayed elsewhere.
final class RestOverlayWindow: NSPanel {
    var isPrimaryDisplay: Bool {
        didSet { headingLabel?.font = .systemFont(ofSize: isPrimaryDisplay ? 26 : 22, weight: .regular) }
    }
    private var dimView: NSView!
    private var messageStack: NSStackView!
    private var headingLabel: NSTextField!
    private var countdownLabel: NSTextField!
    private var hasSubmittedAction = false
    private var isCleanedUp = false
    private var heldModifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
    private let reduceMotion: () -> Bool
    private let onEnd: () -> Void

    init(screenFrame: CGRect, isPrimaryDisplay: Bool = true,
         reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
         onEnd: @escaping () -> Void = { RestController.shared.cancelRest() }) {
        self.isPrimaryDisplay = isPrimaryDisplay
        self.reduceMotion = reduceMotion
        self.onEnd = onEnd
        super.init(contentRect: screenFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setFrame(screenFrame, display: true)
        title = L("休息一下")
        setAccessibilityLabel(title)
        level = .screenSaver + 1
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isFloatingPanel = true
        isReleasedWhenClosed = false
        setupContent()
    }

    private func setupContent() {
        guard let content = contentView else { return }
        dimView = NSView(frame: DisplayLayout.contentBounds(for: content.bounds))
        dimView.identifier = NSUserInterfaceItemIdentifier("rest.dim")
        dimView.autoresizingMask = [.width, .height]
        dimView.wantsLayer = true
        dimView.layer?.backgroundColor = NSColor.black.cgColor
        dimView.alphaValue = 0
        content.addSubview(dimView)

        headingLabel = label(L("休息一下"), size: isPrimaryDisplay ? 26 : 22)
        headingLabel.identifier = NSUserInterfaceItemIdentifier("rest.heading")
        let instruction = label(L("看看窗外，伸个懒腰，或喝口水。"), size: 16)
        countdownLabel = label("", size: 13)
        countdownLabel.identifier = NSUserInterfaceItemIdentifier("rest.countdown")
        countdownLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        countdownLabel.textColor = NSColor.white.withAlphaComponent(0.75)

        let end = NSButton(title: L("返回工作"), target: self, action: #selector(endRest))
        end.bezelStyle = .rounded
        end.identifier = NSUserInterfaceItemIdentifier("rest.end")
        end.setAccessibilityIdentifier("rest.end")
        end.setAccessibilityHelp(L("按任意键返回 · 结束后自动恢复"))
        let hint = label(L("按任意键返回 · 结束后自动恢复"), size: 13)
        let stack = NSStackView(views: [headingLabel, instruction, countdownLabel, end, hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 18
        stack.alphaValue = 0
        stack.identifier = NSUserInterfaceItemIdentifier("rest.message")
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        messageStack = stack
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            instruction.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -48)
        ])
        initialFirstResponder = end
    }

    private func label(_ text: String, size: CGFloat) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size)
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

    func showDimmed() {
        dimView?.alphaValue = 0.85
        messageStack?.alphaValue = 1
    }

    private func animateDim(to alpha: CGFloat, duration: TimeInterval, completion: (() -> Void)?) {
        guard let dimView, let messageStack else { completion?(); return }
        let messageAlpha: CGFloat = alpha > 0 ? 1 : 0
        if reduceMotion() {
            dimView.alphaValue = alpha
            messageStack.alphaValue = messageAlpha
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dimView.animator().alphaValue = alpha
            messageStack.animator().alphaValue = messageAlpha
        }, completionHandler: completion)
    }

    @objc private func endRest() {
        guard !hasSubmittedAction, !isCleanedUp else { return }
        hasSubmittedAction = true
        // Close after event dispatch, without a fade-out delay. Invalidated windows
        // cannot dismiss a subsequent session after a display or lifecycle change.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isCleanedUp else { return }
            self.onEnd()
        }
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            endRest()
            return
        }
        if event.type == .flagsChanged {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let newlyPressed = modifiers.subtracting(heldModifiers)
            heldModifiers = modifiers
            if !newlyPressed.isEmpty { endRest() }
            return
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        endRest()
        return true
    }

    override func keyDown(with event: NSEvent) { endRest() }
    override func cancelOperation(_ sender: Any?) { endRest() }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    func stopAllAnimations() {
        dimView?.layer?.removeAllAnimations()
        messageStack?.layer?.removeAllAnimations()
    }

    func cleanup() {
        isCleanedUp = true
        stopAllAnimations()
        contentView?.subviews.forEach { $0.removeFromSuperview() }
        dimView = nil
        messageStack = nil
        headingLabel = nil
        countdownLabel = nil
    }
}
