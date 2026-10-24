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
            XCTAssertEqual(end?.title, L("提前结束"))
            XCTAssertEqual(postpone?.title, ReminderPresentation.defaultSnoozeTitle())
            let heading = control("rest.heading", in: window) as? NSTextField
            let countdown = control("rest.countdown", in: window) as? NSTextField
            XCTAssertGreaterThan(heading?.font?.pointSize ?? 0, countdown?.font?.pointSize ?? 0,
                                 "Looking away is the instruction; the timer is secondary")
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

    func testLongFrenchReminderTextAndAllActionsFitWithoutOrderingAWindow() {
        onMain {
            let translations = [
                "离屏休息 %@": "Faites une pause loin de votre écran pendant %@",
                "开始后，所有屏幕会渐暗。你可以随时提前结束。":
                    "Lorsque vous commencerez votre pause, tous vos écrans s’assombriront progressivement. Vous pouvez terminer la pause plus tôt à tout moment.",
                "开始休息": "Commencer la pause",
                "%@后再提醒": "Me le rappeler dans %@",
                "跳过 · 下次 %@": "Passer cette pause · prochain rappel prévu à %@"
            ]
            var actions: [String] = []
            let panel = BreakReminderPanel(localize: { translations[$0] ?? $0 },
                onStart: { actions.append("start") }, onPostpone: { actions.append("postpone") },
                onSkip: { actions.append("skip") })
            defer { panel.close() }
            guard let content = panel.contentView else { return XCTFail("Missing panel content") }
            content.layoutSubtreeIfNeeded()
            XCTAssertFalse(panel.isVisible)
            XCTAssertGreaterThan(content.bounds.height, 196, "The panel must grow with its content")
            for id in ["reminderPanel.title", "reminderPanel.detail", "reminderPanel.start",
                       "reminderPanel.postpone", "reminderPanel.skip"] {
                guard let view = control(id, in: panel) else { XCTFail("Missing \(id)"); continue }
                let frame = content.convert(view.bounds, from: view)
                XCTAssertTrue(content.bounds.insetBy(dx: -1, dy: -1).contains(frame), "Clipped \(id): \(frame)")
                XCTAssertGreaterThan(frame.height, 0)
            }
            let detail = control("reminderPanel.detail", in: panel) as? NSTextField
            XCTAssertGreaterThan(detail?.frame.height ?? 0, 30, "Long explanations must wrap")
            for id in ["reminderPanel.start", "reminderPanel.postpone", "reminderPanel.skip"] {
                (control(id, in: panel) as? NSButton)?.performClick(nil)
            }
            XCTAssertEqual(actions, ["start", "postpone", "skip"])
        }
    }

    func testGentleReminderRefreshesItsDurationAndSkipEstimateWhileVisible() {
        onMain {
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let panel = BreakReminderPanel(restSeconds: 20, workMinutes: 40, now: now)
            defer { panel.close() }
            let title = control("reminderPanel.title", in: panel) as? NSTextField
            let skip = control("reminderPanel.skip", in: panel) as? NSButton
            XCTAssertEqual(title?.stringValue, ReminderPresentation.restInvitationTitle(seconds: 20))
            let later = now.addingTimeInterval(120)
            panel.refresh(restSeconds: 600, workMinutes: 15, now: later)
            XCTAssertEqual(title?.stringValue, ReminderPresentation.restInvitationTitle(seconds: 600))
            XCTAssertEqual(skip?.title, ReminderPresentation.skipTitle(workMinutes: 15, now: later))
            XCTAssertEqual(ReminderPresentation.defaultSnoozeSeconds, 300)
        }
    }
}
