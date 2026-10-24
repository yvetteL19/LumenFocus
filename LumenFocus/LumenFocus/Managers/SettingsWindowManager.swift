import Cocoa
import SwiftUI

final class SettingsWindowManager: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowManager()
    private var window: NSWindow?
    private let frameAutosaveName: String?
    private let makeContentViewController: (Bool) -> NSViewController

    init(contentViewControllerFactory: (() -> NSViewController)? = nil,
         frameAutosaveName: String? = "LumenFocusSettingsWindow") {
        self.makeContentViewController = { showGeneral in
            contentViewControllerFactory?() ?? NSHostingController(rootView: SettingsView(showGeneral: showGeneral))
        }
        self.frameAutosaveName = frameAutosaveName
        super.init()
    }

    func showSettings(initiallyShowGeneral: Bool = false) {
        let window = prepareWindow(initiallyShowGeneral: initiallyShowGeneral)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Prepare without ordering or activating, also allowing isolated lifetime tests.
    func prepareWindow(initiallyShowGeneral: Bool = false) -> NSWindow {
        if let window { return window }
        let window = NSWindow(contentViewController: makeContentViewController(initiallyShowGeneral))
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
