import AppKit

/// Coalesces synchronous property publications into one render of their final
/// values on the next main-queue turn. It does not slow down the engine heartbeat.
final class MainQueueUpdateCoalescer {
    private var isScheduled = false
    private let enqueue: (@escaping () -> Void) -> Void

    init(enqueue: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }) {
        self.enqueue = enqueue
    }

    func schedule(_ update: @escaping () -> Void) {
        guard !isScheduled else { return }
        isScheduled = true
        enqueue { [weak self] in
            guard let self else { return }
            self.isScheduled = false
            update()
        }
    }
}

/// The popover keeps its native shell; its observing SwiftUI tree exists only
/// while presented. The factory also keeps lifetime tests free of app singletons.
final class PopoverContentController: NSObject, NSPopoverDelegate {
    private let makeContent: () -> NSViewController

    init(makeContent: @escaping () -> NSViewController) {
        self.makeContent = makeContent
        super.init()
    }

    func prepare(_ popover: NSPopover) {
        popover.delegate = self
        if popover.contentViewController == nil { popover.contentViewController = makeContent() }
    }

    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover, !popover.isShown else { return }
        popover.contentViewController = nil
    }
}
