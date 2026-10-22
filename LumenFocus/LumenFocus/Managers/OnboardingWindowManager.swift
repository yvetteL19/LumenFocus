import Cocoa
import SwiftUI

extension Notification.Name {
    static let lumenFocusOnboardingCompleted = Notification.Name("LumenFocusOnboardingCompleted")
}

final class OnboardingWindowManager: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowManager()
    private var onboardingWindow: NSWindow?
    private var completion: (() -> Void)?

    func showOnboarding(allowClose: Bool = true, completion: @escaping () -> Void) {
        if let window = onboardingWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        self.completion = completion
        let controller = NSHostingController(rootView: OnboardingView())
        let available = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1280, height: 800)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: min(540, available.width - 40), height: min(600, available.height - 60)), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = L("欢迎")
        window.contentViewController = controller
        window.minSize = NSSize(width: 460, height: 440)
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

    func windowWillClose(_ notification: Notification) {
        OnboardingDemo.shared.cancel()
        // Closing is an explicit way to accept the existing defaults, not a trap
        // that reopens the guide on the next launch.
        AppSettings.shared.hasCompletedOnboarding = true
        let callback = completion
        completion = nil
        onboardingWindow = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            callback?()
            NotificationCenter.default.post(name: .lumenFocusOnboardingCompleted, object: nil)
        }
    }
}
