import AppKit
import SwiftUI

final class ReminderPauseWindowManager: NSObject, NSWindowDelegate {
    static let shared = ReminderPauseWindowManager()
    private var window: NSWindow?

    func show() {
        guard AppSettings.shared.remindersEnabled else { return }
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = ReminderPauseView(onConfirm: { [weak self] duration in
            TimerManager.shared.pause(duration: duration)
            self?.close()
        }, onCancel: { [weak self] in self?.close() })
        let controller = NSHostingController(rootView: view.frame(width: 440))
        let window = NSWindow(contentViewController: controller)
        window.title = L("暂停提醒")
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 440, height: max(280, controller.view.fittingSize.height)))
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        closing.contentViewController = nil
        closing.contentView = nil
        closing.delegate = nil
        window = nil
    }
}
