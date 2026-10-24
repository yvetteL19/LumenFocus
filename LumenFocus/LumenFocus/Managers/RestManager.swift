import Cocoa
import Combine

/// Renders one non-activating mask per display. No invitations, app detection or media control.
final class RestManager {
    static let shared = RestManager()
    private var overlayWindows: [UInt32: RestOverlayWindow] = [:]
    private var primaryDisplayID: UInt32?
    private var isPresentingRest = false
    private var cancellables = Set<AnyCancellable>()
    private let appState = AppState.shared
    private let restController = RestController.shared

    private init() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.screensChanged() }
            .store(in: &cancellables)
        restController.stage
            // Synchronous delivery removes masks before the system goes to sleep.
            .sink { [weak self] stage in self?.render(stage) }
            .store(in: &cancellables)
        appState.$remainingSeconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] seconds in self?.overlayWindows.values.forEach { $0.updateCountdown(seconds: seconds) } }
            .store(in: &cancellables)
    }

    private func render(_ stage: RestStage) {
        switch stage {
        case .idle:
            removeOverlays()
        case .fadingIn:
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
        OnboardingDemo.shared.cancel()
        isPresentingRest = true
        primaryDisplayID = nil
    }

    private func displayLayout() -> [DisplayLayout.Screen] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return DisplayLayout.Screen(id: number.uint32Value, frame: screen.frame, visibleFrame: screen.visibleFrame)
        }
    }

    @discardableResult
    private func reconcileOverlays(isInitialPresentation: Bool) -> [RestOverlayWindow] {
        let screens = displayLayout()
        let update = DisplayLayout.update(existingFrames: overlayWindows.mapValues(\.frame), screens: screens,
                                          retaining: primaryDisplayID, pointer: NSEvent.mouseLocation)
        let overlayWasKey = overlayWindows.values.contains(where: \.isKeyWindow)
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
            if restController.stage.value != .fadingIn { window.showDimmed() }
            window.orderFrontRegardless()
            overlayWindows[screen.id] = window
            inserted.append(window)
        }
        // Nonactivating panels borrow keyboard focus without activating LumenFocus.
        // AppKit restores the prior key focus when the panel closes; no app is activated here.
        let needsReplacementKeyWindow = overlayWasKey && !overlayWindows.values.contains(where: \.isKeyWindow)
        if isInitialPresentation || needsReplacementKeyWindow,
           let primaryDisplayID, let key = overlayWindows[primaryDisplayID] {
            key.makeKeyAndOrderFront(nil)
        }
        return inserted
    }

    private func removeOverlays() {
        let windows = Array(overlayWindows.values)
        overlayWindows.removeAll()
        primaryDisplayID = nil
        isPresentingRest = false
        windows.forEach { $0.cleanup(); $0.orderOut(nil); $0.close() }
    }

    private func screensChanged() {
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
