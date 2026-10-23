//
//  StatisticsWindowManager.swift
//  LumenFocus
//
//  Hosts the detailed StatisticsView in a standalone NSWindow.
//

import Cocoa
import SwiftUI

final class StatisticsWindowManager {
    static let shared = StatisticsWindowManager()
    private var window: NSWindow?

    private init() {}

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(rootView: StatisticsView())
        let w = NSWindow(contentViewController: controller)
        w.title = L("统计")
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.contentMinSize = NSSize(width: 640, height: 500)
        let available = NSScreen.main?.visibleFrame.size ?? NSSize(width: 800, height: 800)
        w.setContentSize(NSSize(width: min(760, available.width - 40),
                               height: min(700, available.height - 80)))
        w.center()
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
