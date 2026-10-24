import Cocoa
import SwiftUI

extension Notification.Name {
    static let lumenFocusOnboardingCompleted = Notification.Name("LumenFocusOnboardingCompleted")
}

final class OnboardingWindowManager: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowManager()
    private var onboardingWindow: NSWindow?
    private var completion: (() -> Void)?
    private var didSave = false
    private var isInitialSetup = false

    func showOnboarding(allowClose: Bool = true, completion: @escaping () -> Void) {
        if let window = onboardingWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        self.completion = completion
        didSave = false
        isInitialSetup = !AppSettings.shared.hasCompletedOnboarding
        let controller = NSHostingController(rootView: OnboardingView())
        let available = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1280, height: 800)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: min(540, available.width - 40), height: min(600, available.height - 60)), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = L("欢迎")
        window.contentViewController = controller
        window.contentMinSize = NSSize(width: 460, height: 440)
        // A hosting controller can replace the initial frame with its minimum fitting size.
        window.setContentSize(NSSize(width: min(540, available.width - 40),
                                     height: min(600, available.height - 60)))
        window.level = .normal
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = self
        window.center()
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { onboardingWindow?.close() }

    /// Only the successfully saved draft may start reminders and reveal the menu.
    func finishSetup() {
        guard onboardingWindow != nil else { return }
        didSave = true
        onboardingWindow?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === onboardingWindow else { return }
        OnboardingDemo.shared.cancel()
        let callback = didSave ? completion : nil
        let shouldStart = didSave
        let shouldExit = isInitialSetup && !didSave
        completion = nil
        window.contentViewController = nil
        window.contentView = nil
        window.delegate = nil
        onboardingWindow = nil
        guard shouldStart else {
            if shouldExit { DispatchQueue.main.async { NSApp.terminate(nil) } }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            callback?()
            NotificationCenter.default.post(name: .lumenFocusOnboardingCompleted, object: nil)
        }
    }
}
