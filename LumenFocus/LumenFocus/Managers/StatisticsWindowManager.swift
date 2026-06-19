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
        w.title = "统计"
        w.setContentSize(NSSize(width: 600, height: 560))
        w.center()
        w.styleMask = [.titled, .closable, .miniaturizable]
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
