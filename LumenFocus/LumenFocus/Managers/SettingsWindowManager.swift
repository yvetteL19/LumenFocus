//
//  SettingsWindowManager.swift
//  LumenFocus
//

import Cocoa
import SwiftUI

class SettingsWindowManager {
    static let shared = SettingsWindowManager()
    private var window: NSWindow?

    private init() {}

    func showSettings() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView()
        let controller = NSHostingController(rootView: view)

        let w = NSWindow(contentViewController: controller)
        w.title = L("LumenFocus 设置")
        w.setContentSize(NSSize(width: 500, height: 600))
        w.center()
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false

        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
    }
}
