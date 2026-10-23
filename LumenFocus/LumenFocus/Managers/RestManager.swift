import Cocoa
import Combine

/// Renders the current reminder/rest state without deciding when a rest is due.
final class RestManager {
    static let shared = RestManager()
    private var overlayWindows: [UInt32: RestOverlayWindow] = [:]
    private var primaryDisplayID: UInt32?
    private var isPresentingRest = false
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
            // Like the rest stage, the UI projection is published on the main
            // thread. A sleep/lock transition must hide the panel immediately.
            .sink { [weak self] phase in
                if phase == .reminderDue { self?.showReminder() } else { self?.hideReminder() }
            }
            .store(in: &cancellables)
        appState.$remainingSeconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] seconds in self?.overlayWindows.values.forEach { $0.updateCountdown(seconds: seconds) } }
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
            beginPresentationIfNeeded()
            let inserted = reconcileOverlays(isInitialPresentation: true)
            inserted.forEach { $0.fadeIn(duration: RestController.fadeInDuration) }
        case .midRest:
            let initial = !isPresentingRest
            beginPresentationIfNeeded()
            _ = reconcileOverlays(isInitialPresentation: initial)
            overlayWindows.values.forEach { $0.showDimmed() }
        case .fadingOut:
            overlayWindows.values.forEach { $0.fadeOut(duration: RestController.fadeOutDuration) }
        }
    }

    private func beginPresentationIfNeeded() {
        guard !isPresentingRest else { return }
        isPresentingRest = true
        // A hotkey can arrive before an app-activation notification is delivered.
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        returnApplication = lastExternalApplication
        primaryDisplayID = nil
    }

    private func displayLayout() -> [DisplayLayout.Screen] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return DisplayLayout.Screen(id: number.uint32Value, frame: screen.frame, visibleFrame: screen.visibleFrame)
        }
    }

    /// Reuse unaffected windows so hotplug does not restart their dimming or steal focus.
    @discardableResult
    private func reconcileOverlays(isInitialPresentation: Bool) -> [RestOverlayWindow] {
        let screens = displayLayout()
        let update = DisplayLayout.update(existingFrames: overlayWindows.mapValues(\.frame), screens: screens,
                                          retaining: primaryDisplayID, pointer: NSEvent.mouseLocation)
        let overlayWasKey = overlayWindows.values.contains(where: \.isKeyWindow)
        let appWasActive = NSApp.isActive
        primaryDisplayID = update.primaryID
        for id in update.removedIDs {
            guard let window = overlayWindows.removeValue(forKey: id) else { continue }
            window.cleanup()
            window.orderOut(nil)
            window.close()
        }
        var inserted: [RestOverlayWindow] = []
        for screen in screens {
            if let window = overlayWindows[screen.id] {
                window.isPrimaryDisplay = screen.id == primaryDisplayID
                if update.resizedIDs.contains(screen.id) { window.setFrame(screen.frame, display: true) }
                continue
            }
            let window = RestOverlayWindow(screenFrame: screen.frame, isPrimaryDisplay: screen.id == primaryDisplayID)
            window.updateCountdown(seconds: appState.remainingSeconds)
            // New windows join the current stage; existing displays keep their animation.
            if restController.stage.value != .fadingIn { window.showDimmed() }
            window.orderFrontRegardless()
            overlayWindows[screen.id] = window
            inserted.append(window)
        }
        let shouldActivate = RestFocusPolicy.shouldActivate(isInitialPresentation: isInitialPresentation,
                                                            hasDisplays: !overlayWindows.isEmpty)
        if shouldActivate { NSApp.activate(ignoringOtherApps: true) }
        let needsReplacementKeyWindow = appWasActive && overlayWasKey && !overlayWindows.values.contains(where: \.isKeyWindow)
        if shouldActivate || needsReplacementKeyWindow,
           let primaryDisplayID, let key = overlayWindows[primaryDisplayID] {
            key.makeKeyAndOrderFront(nil)
        }
        return inserted
    }

    private func removeOverlays(returnFocus: Bool) {
        let overlayWasKey = overlayWindows.values.contains(where: \.isKeyWindow)
        let application = returnApplication
        let shouldRestore = returnFocus && RestFocusPolicy.shouldRestore(appIsActive: NSApp.isActive,
            overlayWasKey: overlayWasKey, returnAppIsRunning: application.map { !$0.isTerminated } ?? false)
        let windows = Array(overlayWindows.values)
        overlayWindows.removeAll()
        primaryDisplayID = nil
        isPresentingRest = false
        returnApplication = nil
        windows.forEach { $0.cleanup(); $0.orderOut(nil); $0.close() }
        if shouldRestore { application?.activate(options: [.activateIgnoringOtherApps]) }
    }

    private func showReminder() {
        let screens = displayLayout()
        let selection = DisplayLayout.update(existingFrames: [:], screens: screens, retaining: nil, pointer: NSEvent.mouseLocation)
        guard reminderPanel == nil, let screen = screens.first(where: { $0.id == selection.primaryID }) else { return }
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

    private func position(_ panel: NSPanel, on screen: DisplayLayout.Screen) {
        panel.setFrameOrigin(DisplayLayout.reminderOrigin(panelSize: panel.frame.size, visibleFrame: screen.visibleFrame))
    }

    private func screensChanged() {
        // Recreate a due reminder if it initially had no available display.
        if appState.currentPhase == .reminderDue {
            let screens = displayLayout()
            let selection = DisplayLayout.update(existingFrames: [:], screens: screens, retaining: nil, pointer: NSEvent.mouseLocation)
            if let panel = reminderPanel, let screen = screens.first(where: { $0.id == selection.primaryID }) {
                position(panel, on: screen)
            } else if screens.isEmpty {
                hideReminder()
            } else {
                showReminder()
            }
        } else {
            hideReminder()
        }
        let stage = restController.stage.value
        guard stage != .idle else { return }
        let inserted = reconcileOverlays(isInitialPresentation: false)
        switch stage {
        case .fadingOut: inserted.forEach { $0.fadeOut(duration: RestController.fadeOutDuration) }
        case .fadingIn, .midRest: inserted.forEach { $0.showDimmed() }
        case .idle: break
        }
    }
}

/// A local, actionable reminder; no notification permission and no app activation required.
final class BreakReminderPanel: NSPanel {
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
