import AppKit
import XCTest
@testable import LumenFocus

final class RestPresentationTests: XCTestCase {
    private func onMain(_ action: () -> Void) {
        if Thread.isMainThread { action() } else { DispatchQueue.main.sync(execute: action) }
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func control(_ identifier: String, in window: NSWindow) -> NSView? {
        guard let content = window.contentView else { return nil }
        return descendants(of: content).first { $0.identifier?.rawValue == identifier }
    }

    func testFocusIsClaimedInitiallyButNeverByAHotplugRebuild() {
        XCTAssertTrue(RestFocusPolicy.shouldActivate(isInitialPresentation: true, hasDisplays: true))
        XCTAssertFalse(RestFocusPolicy.shouldActivate(isInitialPresentation: false, hasDisplays: true))
        XCTAssertFalse(RestFocusPolicy.shouldRestore(appIsActive: false, overlayWasKey: true, returnAppIsRunning: true),
                       "A user who switched apps must keep their chosen focus")
        XCTAssertFalse(RestFocusPolicy.shouldRestore(appIsActive: true, overlayWasKey: false, returnAppIsRunning: true),
                       "Do not replace a settings/statistics window the user explicitly opened")
        XCTAssertFalse(RestFocusPolicy.shouldRestore(appIsActive: true, overlayWasKey: true, returnAppIsRunning: false))
        XCTAssertTrue(RestFocusPolicy.shouldRestore(appIsActive: true, overlayWasKey: true, returnAppIsRunning: true))
    }

    func testUnorderedOverlayCoversLocalBoundsOnNegativeDisplayAndResize() {
        onMain {
            let window = RestOverlayWindow(screenFrame: CGRect(x: -1920, y: -180, width: 1920, height: 1080), reduceMotion: { true })
            defer { window.cleanup(); window.close() }
            XCTAssertFalse(window.isVisible)
            XCTAssertEqual(window.frame.origin, CGPoint(x: -1920, y: -180))
            XCTAssertEqual(control("rest.dim", in: window)?.frame, CGRect(x: 0, y: 0, width: 1920, height: 1080))
            window.setFrame(CGRect(x: 0, y: 900, width: 1280, height: 720), display: false)
            XCTAssertEqual(control("rest.dim", in: window)?.frame, CGRect(x: 0, y: 0, width: 1280, height: 720))
        }
    }

    func testReduceMotionChangesOnlyDimmingAndLeavesBothControlsReachable() {
        onMain {
            let window = RestOverlayWindow(screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600), reduceMotion: { true })
            defer { window.cleanup(); window.close() }
            let end = control("rest.end", in: window) as? NSButton
            let postpone = control("rest.postpone", in: window) as? NSButton
            XCTAssertNotNil(end)
            XCTAssertNotNil(postpone)
            XCTAssertTrue(window.initialFirstResponder === end)
            XCTAssertEqual(end?.keyEquivalent, "\u{1b}")
            XCTAssertEqual(end?.keyEquivalentModifierMask, [])
            XCTAssertTrue(end?.nextKeyView === postpone)
            XCTAssertTrue(postpone?.nextKeyView === end)
            var completed = false
            window.fadeIn(duration: 100) { completed = true }
            XCTAssertTrue(completed, "Reduce Motion must not wait for an animation")
            XCTAssertEqual(control("rest.dim", in: window)?.alphaValue, 0.85)
            window.updateCountdown(seconds: -3)
            XCTAssertEqual((control("rest.countdown", in: window) as? NSTextField)?.stringValue, "0:00")
            window.fadeOut(duration: 100)
            XCTAssertEqual(control("rest.dim", in: window)?.alphaValue, 0)
            XCTAssertFalse(end?.isHiddenOrHasHiddenAncestor ?? true)
            XCTAssertFalse(postpone?.isHiddenOrHasHiddenAncestor ?? true)
            XCTAssertTrue(end?.isEnabled ?? false)
            XCTAssertTrue(postpone?.isEnabled ?? false)
        }
    }

    func testEscapeAndRepeatedButtonActionsSubmitOnlyTheFirstChoice() {
        let submitted = expectation(description: "one end action")
        submitted.assertForOverFulfill = true
        var endCount = 0
        var postponeCount = 0
        var window: RestOverlayWindow!
        onMain {
            window = RestOverlayWindow(screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
                onEnd: { endCount += 1; submitted.fulfill() }, onPostpone: { postponeCount += 1 })
            let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
            window.keyDown(with: escape)
            window.cancelOperation(nil)
            (control("rest.postpone", in: window) as? NSButton)?.performClick(nil)
        }
        wait(for: [submitted], timeout: 2)
        onMain { window.cleanup(); window.close() }
        XCTAssertEqual(endCount, 1)
        XCTAssertEqual(postponeCount, 0)
    }

    func testRemovingWindowInvalidatesAnActionStillWaitingOnTheMainQueue() {
        let drained = expectation(description: "main queue drained")
        var calls = 0
        onMain {
            let window = RestOverlayWindow(screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600), onEnd: { calls += 1 })
            window.cancelOperation(nil)
            window.cleanup()
            window.close()
            DispatchQueue.main.async { drained.fulfill() }
        }
        wait(for: [drained], timeout: 2)
        XCTAssertEqual(calls, 0, "An interrupted or removed overlay cannot act on a later rest")
    }

    func testGentlePanelConstructionDoesNotActivateOrTakeTheKeyWindow() {
        onMain {
            let key = NSApp.keyWindow
            let active = NSApp.isActive
            let panel = BreakReminderPanel()
            defer { panel.close() }
            XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
            XCTAssertFalse(panel.canBecomeKey)
            XCTAssertFalse(panel.canBecomeMain)
            XCTAssertFalse(panel.isVisible)
            XCTAssertTrue(NSApp.keyWindow === key)
            XCTAssertEqual(NSApp.isActive, active)
            let buttons = panel.contentView.map { descendants(of: $0).compactMap { $0 as? NSButton } } ?? []
            XCTAssertEqual(buttons.count, 3)
            XCTAssertTrue(buttons.allSatisfy { $0.isEnabled && !$0.title.isEmpty })
        }
    }
}
