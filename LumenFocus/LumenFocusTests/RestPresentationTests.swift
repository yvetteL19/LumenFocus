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

    private func key(_ code: UInt16, characters: String, window: NSWindow,
                     flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    func testConstructionIsNonactivatingAndDoesNotChangeFocus() {
        onMain {
            let key = NSApp.keyWindow
            let active = NSApp.isActive
            let window = RestOverlayWindow(screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600))
            defer { window.cleanup(); window.close() }
            XCTAssertTrue(window.styleMask.contains(.nonactivatingPanel))
            XCTAssertFalse(window.isVisible)
            XCTAssertTrue(window.canBecomeKey, "The layer receives the one key used to dismiss it")
            XCTAssertFalse(window.canBecomeMain)
            XCTAssertTrue(NSApp.keyWindow === key)
            XCTAssertEqual(NSApp.isActive, active)
        }
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

    func testTextAndMaskAppearTogetherWithOneOptionalExitControl() {
        onMain {
            let window = RestOverlayWindow(screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600), reduceMotion: { true })
            defer { window.cleanup(); window.close() }
            XCTAssertEqual(control("rest.dim", in: window)?.alphaValue, 0)
            XCTAssertEqual(control("rest.message", in: window)?.alphaValue, 0)
            let buttons = window.contentView.map { descendants(of: $0).compactMap { $0 as? NSButton } } ?? []
            XCTAssertEqual(buttons.count, 1)
            XCTAssertEqual(buttons.first?.title, L("返回工作"))
            XCTAssertTrue(window.initialFirstResponder === buttons.first)
            let heading = control("rest.heading", in: window) as? NSTextField
            let countdown = control("rest.countdown", in: window) as? NSTextField
            XCTAssertGreaterThan(heading?.font?.pointSize ?? 0, countdown?.font?.pointSize ?? 0)
            var completed = false
            window.fadeIn(duration: 100) { completed = true }
            XCTAssertTrue(completed, "Reduce Motion does not wait for an animation")
            XCTAssertEqual(control("rest.dim", in: window)?.alphaValue, 0.85)
            XCTAssertEqual(control("rest.message", in: window)?.alphaValue, 1)
            window.updateCountdown(seconds: -3)
            XCTAssertEqual(countdown?.stringValue, "0:00")
            window.fadeOut(duration: 100)
            XCTAssertEqual(control("rest.dim", in: window)?.alphaValue, 0)
            XCTAssertEqual(control("rest.message", in: window)?.alphaValue, 0)
        }
    }

    func testAnyOrdinaryKeyIsConsumedAndDismissesEvenDuringFadeIn() {
        let cases: [(UInt16, String)] = [(0, "a"), (49, " "), (36, "\r"), (48, "\t"), (123, "\u{f702}"), (53, "\u{1b}")]
        let submitted = expectation(description: "each key dismisses its overlay")
        submitted.expectedFulfillmentCount = cases.count
        var windows: [RestOverlayWindow] = []
        onMain {
            for (code, characters) in cases {
                let window = RestOverlayWindow(screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
                                               onEnd: { submitted.fulfill() })
                windows.append(window)
                // Dispatch at the window: a focused button must not swallow Space or Tab.
                window.sendEvent(key(code, characters: characters, window: window))
            }
        }
        wait(for: [submitted], timeout: 2)
        onMain { windows.forEach { $0.cleanup(); $0.close() } }
    }

    func testShortcutAndRepeatedExitActionsSubmitOnlyOnce() {
        let submitted = expectation(description: "one end action")
        submitted.assertForOverFulfill = true
        var calls = 0
        var window: RestOverlayWindow!
        onMain {
            window = RestOverlayWindow(screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
                                       onEnd: { calls += 1; submitted.fulfill() })
            XCTAssertTrue(window.performKeyEquivalent(with: key(0, characters: "a", window: window, flags: .command)))
            window.cancelOperation(nil)
            (control("rest.end", in: window) as? NSButton)?.performClick(nil)
        }
        wait(for: [submitted], timeout: 2)
        onMain { window.cleanup(); window.close() }
        XCTAssertEqual(calls, 1)
    }

    func testReleasingShortcutModifiersDoesNotDismissButNewModifierPressDoes() {
        let submitted = expectation(description: "new Shift key press dismisses")
        var calls = 0
        var window: RestOverlayWindow!
        onMain {
            window = RestOverlayWindow(screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
                                       onEnd: { calls += 1; submitted.fulfill() })
            func flags(_ modifiers: NSEvent.ModifierFlags) -> NSEvent {
                NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: modifiers, timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                    isARepeat: false, keyCode: 56)!
            }
            window.sendEvent(flags([]))
            DispatchQueue.main.async {
                XCTAssertEqual(calls, 0, "Releasing the hotkey that opened the mask must not close it")
                window.sendEvent(flags(.shift))
            }
        }
        wait(for: [submitted], timeout: 2)
        onMain { window.cleanup(); window.close() }
        XCTAssertEqual(calls, 1)
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
        XCTAssertEqual(calls, 0, "A removed overlay cannot act on a later rest")
    }
}
