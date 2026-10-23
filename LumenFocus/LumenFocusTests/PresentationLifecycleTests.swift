import AppKit
import Combine
import SwiftUI
import XCTest
@testable import LumenFocus

final class PresentationLifecycleTests: XCTestCase {
    private final class Projection: ObservableObject {
        @Published var remaining = 600
        @Published var progress = 1.0
        @Published var phase = "working"
    }

    private struct RenderedValue: Equatable {
        let remaining: Int
        let progress: Double
        let phase: String
    }

    private func onMain(_ action: () -> Void) {
        if Thread.isMainThread { action() } else { DispatchQueue.main.sync(execute: action) }
    }

    func testPublishedPropertyBurstRendersTheFinalProjectionOnce() {
        let model = Projection()
        var queued: [() -> Void] = []
        let coalescer = MainQueueUpdateCoalescer(enqueue: { queued.append($0) })
        var rendered: [RenderedValue] = []
        let subscription = model.objectWillChange.sink {
            coalescer.schedule {
                rendered.append(RenderedValue(remaining: model.remaining, progress: model.progress, phase: model.phase))
            }
        }
        withExtendedLifetime(subscription) {
            model.remaining = 20
            model.progress = 0.5
            model.phase = "resting"
            XCTAssertTrue(rendered.isEmpty, "Published sends before assignment; rendering must wait for the complete projection")
            XCTAssertEqual(queued.count, 1)
            queued.removeFirst()()
            XCTAssertEqual(rendered, [RenderedValue(remaining: 20, progress: 0.5, phase: "resting")])

            model.remaining = 19
            model.progress = 0.475
            XCTAssertEqual(queued.count, 1)
            queued.removeFirst()()
            XCTAssertEqual(rendered.last, RenderedValue(remaining: 19, progress: 0.475, phase: "resting"))
            XCTAssertEqual(rendered.count, 2, "A later heartbeat must still update normally")
        }
    }

    func testChangesDuringRenderingAreNotLost() {
        let model = Projection()
        var queued: [() -> Void] = []
        let coalescer = MainQueueUpdateCoalescer(enqueue: { queued.append($0) })
        var rendered: [Int] = []
        let subscription = model.objectWillChange.sink {
            coalescer.schedule {
                rendered.append(model.remaining)
                if rendered.count == 1 { model.remaining = 18 }
            }
        }
        withExtendedLifetime(subscription) {
            model.remaining = 19
            queued.removeFirst()()
            XCTAssertEqual(rendered, [19])
            XCTAssertEqual(queued.count, 1)
            queued.removeFirst()()
            XCTAssertEqual(rendered, [19, 18])
        }
    }

    func testClosingSettingsReleasesHostingTreeAndReopensFreshWithoutActivation() {
        onMain {
            weak var releasedController: NSViewController?
            weak var releasedView: NSView?
            var creations = 0
            let keyWindow = NSApp.keyWindow
            let wasActive = NSApp.isActive
            let manager = SettingsWindowManager(contentViewControllerFactory: {
                creations += 1
                let controller = NSHostingController(rootView: Text("Isolated settings content"))
                releasedController = controller
                releasedView = controller.view
                return controller
            }, frameAutosaveName: nil)

            autoreleasepool {
                let window = manager.prepareWindow()
                XCTAssertTrue(window === manager.prepareWindow())
                XCTAssertEqual(creations, 1)
                XCTAssertFalse(window.isVisible)
                XCTAssertNotNil(releasedController)
                window.close()
                XCTAssertNil(window.contentViewController)
            }
            XCTAssertNil(releasedController)
            XCTAssertNil(releasedView, "Clearing only the controller is insufficient if NSWindow retains the hosting view")
            autoreleasepool {
                let reopened = manager.prepareWindow()
                XCTAssertEqual(creations, 2)
                XCTAssertNotNil(reopened.contentViewController)
                XCTAssertFalse(reopened.isVisible)
                reopened.close()
            }
            XCTAssertNil(releasedController)
            XCTAssertTrue(NSApp.keyWindow === keyWindow)
            XCTAssertEqual(NSApp.isActive, wasActive)
        }
    }

    func testClosingStatisticsReleasesHostingTreeAndCanReopen() {
        onMain {
            weak var releasedController: NSViewController?
            weak var releasedView: NSView?
            var creations = 0
            let manager = StatisticsWindowManager(contentViewControllerFactory: {
                creations += 1
                let controller = NSHostingController(rootView: Text("Isolated statistics content"))
                releasedController = controller
                releasedView = controller.view
                return controller
            })
            autoreleasepool {
                let window = manager.prepareWindow()
                XCTAssertTrue(window === manager.prepareWindow())
                window.close()
                XCTAssertNil(window.contentViewController)
            }
            XCTAssertNil(releasedController)
            XCTAssertNil(releasedView)
            autoreleasepool {
                let reopened = manager.prepareWindow()
                XCTAssertEqual(creations, 2)
                XCTAssertNotNil(reopened.contentViewController)
                reopened.close()
            }
            XCTAssertNil(releasedController)
        }
    }

    func testPopoverCloseReleasesHostingTreeAndNextPresentationGetsFreshContent() {
        onMain {
            let popover = NSPopover()
            weak var releasedController: NSViewController?
            weak var releasedView: NSView?
            var creations = 0
            let lifetime = PopoverContentController {
                creations += 1
                let controller = NSHostingController(rootView: Text("Isolated menu content"))
                releasedController = controller
                releasedView = controller.view
                return controller
            }
            autoreleasepool {
                lifetime.prepare(popover)
                lifetime.prepare(popover)
                XCTAssertEqual(creations, 1)
                XCTAssertTrue(popover.delegate === lifetime)
                XCTAssertFalse(popover.isShown)
                // Drive the same native delegate callback without ordering a window.
                lifetime.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: popover))
                XCTAssertNil(popover.contentViewController)
            }
            XCTAssertNil(releasedController)
            XCTAssertNil(releasedView)
            autoreleasepool {
                lifetime.prepare(popover)
                XCTAssertEqual(creations, 2)
                XCTAssertNotNil(popover.contentViewController)
                lifetime.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: popover))
            }
            XCTAssertNil(releasedController)
        }
    }
}
