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
        Publishers.Merge3(appState.$todayWorkDuration.map { _ in () },
                          AppSettings.shared.$restDurationSeconds.map { _ in () },
                          AppSettings.shared.$workDurationMinutes.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let panel = self?.reminderPanel else { return }
                panel.refresh(restSeconds: AppSettings.shared.restDurationSeconds,
                              workMinutes: AppSettings.shared.workDurationMinutes)
            }
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
        let panel = BreakReminderPanel(restSeconds: AppSettings.shared.restDurationSeconds,
                                       workMinutes: AppSettings.shared.workDurationMinutes)
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
    private let localize: (String) -> String
    private let onStart: () -> Void
    private let onPostpone: () -> Void
    private let onSkip: () -> Void
    private var titleLabel: NSTextField!
    private var skipButton: NSButton!
    private var contentStack: NSStackView!
    private var lastRefresh: String?
    private let panelWidth: CGFloat = 420
    private let contentWidth: CGFloat = 380

    init(restSeconds: Int = 300, workMinutes: Int = 40, now: Date = Date(),
         localize: @escaping (String) -> String = { L($0) },
         onStart: @escaping () -> Void = { TimerManager.shared.triggerManualRest() },
         onPostpone: @escaping () -> Void = { TimerManager.shared.snoozeReminder(by: ReminderPresentation.defaultSnoozeSeconds) },
         onSkip: @escaping () -> Void = { TimerManager.shared.skipReminder() }) {
        self.localize = localize
        self.onStart = onStart
        self.onPostpone = onPostpone
        self.onSkip = onSkip
        super.init(contentRect: NSRect(x: 0, y: 0, width: 420, height: 1), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
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
        titleLabel = NSTextField(wrappingLabelWithString: "")
        titleLabel.font = .systemFont(ofSize: 18, weight: .medium)
        titleLabel.identifier = NSUserInterfaceItemIdentifier("reminderPanel.title")
        let detail = NSTextField(wrappingLabelWithString: localize("开始后，所有屏幕会渐暗。你可以随时提前结束。"))
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabelColor
        detail.identifier = NSUserInterfaceItemIdentifier("reminderPanel.detail")
        [titleLabel!, detail].forEach {
            $0.preferredMaxLayoutWidth = contentWidth
            $0.maximumNumberOfLines = 0
            $0.lineBreakMode = .byWordWrapping
        }
        let start = NSButton(title: localize("开始休息"), target: self, action: #selector(startBreak))
        let postpone = NSButton(title: ReminderPresentation.defaultSnoozeTitle(localize: localize), target: self, action: #selector(postponeBreak))
        skipButton = NSButton(title: "", target: self, action: #selector(skipBreak))
        start.identifier = NSUserInterfaceItemIdentifier("reminderPanel.start")
        postpone.identifier = NSUserInterfaceItemIdentifier("reminderPanel.postpone")
        skipButton.identifier = NSUserInterfaceItemIdentifier("reminderPanel.skip")
        // Vertical actions keep long translations readable without compressing any choice.
        [start, postpone, skipButton!].forEach {
            $0.bezelStyle = .regularSquare
            $0.isBordered = true
            $0.cell?.wraps = true
            $0.cell?.lineBreakMode = .byWordWrapping
            $0.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        }
        contentStack = NSStackView(views: [titleLabel, detail, start, postpone, skipButton])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            contentStack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            contentStack.widthAnchor.constraint(equalToConstant: contentWidth),
            titleLabel.widthAnchor.constraint(equalToConstant: contentWidth),
            detail.widthAnchor.constraint(equalToConstant: contentWidth)
        ])
        refresh(restSeconds: restSeconds, workMinutes: workMinutes, now: now)
        setAccessibilityLabel(localize("LumenFocus 休息提醒"))
    }

    func refresh(restSeconds: Int, workMinutes: Int, now: Date = Date()) {
        // The existing work projection drives this refresh. No extra timer is needed;
        // native text and layout change only when the displayed minute/settings change.
        let key = "\(restSeconds)-\(workMinutes)-\(Int(now.timeIntervalSince1970 / 60))-\(TimeZone.current.identifier)"
        guard key != lastRefresh else { return }
        lastRefresh = key
        titleLabel.stringValue = ReminderPresentation.restInvitationTitle(seconds: restSeconds, localize: localize)
        skipButton.title = ReminderPresentation.skipTitle(workMinutes: workMinutes, now: now, localize: localize)
        for button in contentStack.arrangedSubviews.compactMap({ $0 as? NSButton }) {
            let text = NSAttributedString(string: button.title, attributes: [.font: button.font ?? NSFont.systemFont(ofSize: 13)])
            let height = ceil(text.boundingRect(with: NSSize(width: contentWidth - 24, height: .greatestFiniteMagnitude),
                                               options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
            if let existing = button.constraints.first(where: { $0.identifier == "reminderPanel.buttonHeight" }) {
                existing.constant = max(32, height + 16)
            } else {
                let constraint = button.heightAnchor.constraint(equalToConstant: max(32, height + 16))
                constraint.identifier = "reminderPanel.buttonHeight"
                constraint.isActive = true
            }
        }
        contentView?.layoutSubtreeIfNeeded()
        let height = ceil(contentStack.fittingSize.height) + 40
        // Preserve the upper edge when a live settings change reflows the message.
        let top = frame.maxY
        setContentSize(NSSize(width: panelWidth, height: height))
        setFrameOrigin(NSPoint(x: frame.minX, y: top - frame.height))
        contentView?.layoutSubtreeIfNeeded()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    @objc private func startBreak() { onStart() }
    @objc private func postponeBreak() { onPostpone() }
    @objc private func skipBreak() { onSkip() }
}
