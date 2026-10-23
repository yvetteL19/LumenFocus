import Cocoa
import SwiftUI

final class SettingsWindowManager: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowManager()
    private var window: NSWindow?
    private let frameAutosaveName: String?
    private let makeContentViewController: () -> NSViewController

    init(contentViewControllerFactory: @escaping () -> NSViewController = { NSHostingController(rootView: SettingsView()) },
         frameAutosaveName: String? = "LumenFocusSettingsWindow") {
        self.makeContentViewController = contentViewControllerFactory
        self.frameAutosaveName = frameAutosaveName
        super.init()
    }

    func showSettings() {
        let window = prepareWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Prepare without ordering or activating, also allowing isolated lifetime tests.
    func prepareWindow() -> NSWindow {
        if let window { return window }
        let window = NSWindow(contentViewController: makeContentViewController())
        window.title = L("LumenFocus 设置")
        window.styleMask = [.titled, .closable, .resizable]
        window.contentMinSize = NSSize(width: 520, height: 480)
        window.setContentSize(NSSize(width: 620, height: 600))
        window.isReleasedWhenClosed = false
        window.delegate = self
        if let frameAutosaveName {
            window.setFrameAutosaveName(frameAutosaveName)
            if !window.setFrameUsingName(frameAutosaveName) { window.center() }
        } else {
            window.center()
        }

        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        // NSWindow is retained after its close button is used. Detach both the
        // controller and its view so hidden SwiftUI observations stop as well.
        closing.contentViewController = nil
        closing.contentView = nil
        closing.delegate = nil
        window = nil
    }

    func close() {
        window?.close()
        window = nil
    }
}
