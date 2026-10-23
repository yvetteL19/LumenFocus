import Cocoa
import Combine

/// Renders the current reminder/rest state without deciding when a rest is due.
final class RestManager {
    static let shared = RestManager()
    private var overlayWindows: [RestOverlayWindow] = []
    private var reminderPanel: BreakReminderPanel?
    private var cancellables = Set<AnyCancellable>()
    private var lastExternalApplication: NSRunningApplication?
    private var returnApplication: NSRunningApplication?
    private let appState = AppState.shared
    private let restController = RestController.shared

    private init() {
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.screensChanged() }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.rememberExternalApplication(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            }
            .store(in: &cancellables)
        restController.stage
            // TimerManager publishes on the main thread. Deliver immediately so
            // willSleep removes overlays before the run loop is suspended.
            .sink { [weak self] stage in self?.render(stage) }
            .store(in: &cancellables)
        appState.$currentPhase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                if phase == .reminderDue { self?.showReminder() } else { self?.hideReminder() }
            }
            .store(in: &cancellables)
        appState.$remainingSeconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] seconds in self?.overlayWindows.forEach { $0.updateCountdown(seconds: seconds) } }
            .store(in: &cancellables)
    }

    private func rememberExternalApplication(_ application: NSRunningApplication?) {
        guard let application, application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        lastExternalApplication = application
    }

    private func render(_ stage: RestStage) {
        switch stage {
        case .idle:
            removeOverlays(returnFocus: true)
        case .fadingIn:
            hideReminder()
            guard overlayWindows.isEmpty else { return }
            returnApplication = lastExternalApplication
            createOverlays()
            overlayWindows.forEach { $0.fadeIn(duration: RestController.fadeInDuration) }
        case .midRest:
            if overlayWindows.isEmpty { createOverlays() }
            overlayWindows.forEach { $0.showDimmed() }
        case .fadingOut:
            overlayWindows.forEach { $0.fadeOut(duration: RestController.fadeOutDuration) }
        }
    }

    private func preferredScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func createOverlays() {
        let screens = NSScreen.screens
        // Freeze primary identity before creating/activating windows; NSScreen.main can then change.
        let primary = preferredScreen()
        for screen in screens {
            let window = RestOverlayWindow(screen: screen, isPrimaryDisplay: screen == primary)
            window.updateCountdown(seconds: appState.remainingSeconds)
            window.orderFrontRegardless()
            overlayWindows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        let key = overlayWindows.first(where: \.isPrimaryDisplay) ?? overlayWindows.first
        key?.makeKeyAndOrderFront(nil)
    }

    private func removeOverlays(returnFocus: Bool) {
        let hadOverlays = !overlayWindows.isEmpty
        let windows = overlayWindows
        overlayWindows.removeAll()
        windows.forEach { $0.cleanup(); $0.orderOut(nil); $0.close() }
        if returnFocus, hadOverlays {
            let application = returnApplication
            returnApplication = nil
            if NSApp.isActive, let application, !application.isTerminated {
                application.activate(options: [.activateIgnoringOtherApps])
            }
        }
    }

    private func showReminder() {
        guard reminderPanel == nil, let screen = preferredScreen() else { return }
        let panel = BreakReminderPanel()
        position(panel, on: screen)
        reminderPanel = panel
        // A non-activating panel neither becomes key nor steals the current app's focus.
        panel.orderFrontRegardless()
    }

    private func hideReminder() {
        reminderPanel?.orderOut(nil)
        reminderPanel?.close()
        reminderPanel = nil
    }

    private func position(_ panel: NSPanel, on screen: NSScreen) {
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 16, y: frame.maxY - panel.frame.height - 16))
    }

    private func screensChanged() {
        if let panel = reminderPanel, let screen = preferredScreen() { position(panel, on: screen) }
        let stage = restController.stage.value
        guard stage != .idle else { return }
        removeOverlays(returnFocus: false)
        createOverlays()
        switch stage {
        case .fadingOut: overlayWindows.forEach { $0.showDimmed(); $0.fadeOut(duration: RestController.fadeOutDuration) }
        case .fadingIn, .midRest: overlayWindows.forEach { $0.showDimmed() }
        case .idle: break
        }
    }
}

/// A local, actionable reminder; no notification permission and no app activation required.
private final class BreakReminderPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 410, height: 196), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .windowBackgroundColor
        hasShadow = true
        let content = NSView()
        content.wantsLayer = true
        content.layer?.cornerRadius = 12
        contentView = content
        let title = NSTextField(labelWithString: L("给眼睛一个小空隙"))
        title.font = .systemFont(ofSize: 18, weight: .medium)
        let detail = NSTextField(wrappingLabelWithString: L("准备好再开始，当前工作不会被遮挡。"))
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabelColor
        let start = NSButton(title: L("开始休息"), target: self, action: #selector(startBreak))
        let postpone = NSButton(title: L("5 分钟后再提醒"), target: self, action: #selector(postponeBreak))
        let skip = NSButton(title: L("跳过本次"), target: self, action: #selector(skipBreak))
        [start, postpone, skip].forEach { $0.bezelStyle = .rounded }
        let actions = NSStackView(views: [start, postpone, skip])
        actions.orientation = .horizontal
        actions.spacing = 8
        let stack = NSStackView(views: [title, detail, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            detail.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        setAccessibilityLabel(L("LumenFocus 休息提醒"))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    @objc private func startBreak() { TimerManager.shared.triggerManualRest() }
    @objc private func postponeBreak() { TimerManager.shared.snoozeReminder(by: 300) }
    @objc private func skipBreak() { TimerManager.shared.skipReminder() }
}
