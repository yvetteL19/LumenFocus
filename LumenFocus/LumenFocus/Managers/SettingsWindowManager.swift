import Cocoa
import SwiftUI

final class SettingsWindowManager {
    static let shared = SettingsWindowManager()
    private var window: NSWindow?
    private let frameAutosaveName = "LumenFocusSettingsWindow"

    private init() {}

    func showSettings() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: controller)
        window.title = L("LumenFocus 设置")
        window.styleMask = [.titled, .closable, .resizable]
        window.contentMinSize = NSSize(width: 520, height: 480)
        window.setContentSize(NSSize(width: 620, height: 600))
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName(frameAutosaveName)
        if !window.setFrameUsingName(frameAutosaveName) { window.center() }

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
    }
}
