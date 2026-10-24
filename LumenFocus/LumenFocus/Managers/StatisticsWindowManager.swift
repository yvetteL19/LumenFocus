//
//  StatisticsWindowManager.swift
//  LumenFocus
//
//  Hosts the detailed StatisticsView in a standalone NSWindow.
//

import Cocoa
import SwiftUI

final class StatisticsWindowManager: NSObject, NSWindowDelegate {
    static let shared = StatisticsWindowManager()
    private var window: NSWindow?
    private let makeContentViewController: () -> NSViewController

    init(contentViewControllerFactory: @escaping () -> NSViewController = { NSHostingController(rootView: StatisticsView()) }) {
        makeContentViewController = contentViewControllerFactory
        super.init()
    }

    func show() {
        let window = prepareWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func prepareWindow() -> NSWindow {
        if let window { return window }
        let w = NSWindow(contentViewController: makeContentViewController())
        w.title = L("休息记录")
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.contentMinSize = NSSize(width: 640, height: 500)
        let available = NSScreen.main?.visibleFrame.size ?? NSSize(width: 800, height: 800)
        w.setContentSize(NSSize(width: min(760, available.width - 40),
                               height: min(700, available.height - 80)))
        w.center()
        w.isReleasedWhenClosed = false
        w.delegate = self

        window = w
        return w
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
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
