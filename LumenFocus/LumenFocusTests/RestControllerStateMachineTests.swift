import XCTest
import Combine
@testable import LumenFocus

/// Tests only the presentation adapter; no global timer, sound, or user defaults are touched.
final class RestControllerStateMachineTests: XCTestCase {
    func testStagesGiveTwentySecondsToActualRestAndDefaultToLookingAway() {
        var starts = 0
        var stops = 0
        let controller = RestController(onCancel: {}, onSnooze: { _ in },
                                        onStartSound: { starts += 1 }, onStopSound: { stops += 1 })
        let id = UUID()
        func render(_ elapsed: TimeInterval) {
            controller.render(.init(id: id, duration: 20, elapsed: elapsed,
                                    fadeInDuration: 2, fadeOutDuration: 1))
        }
        render(0)
        XCTAssertEqual(controller.stage.value, .fadingIn)
        render(2)
        XCTAssertEqual(controller.stage.value, .midRest)
        XCTAssertEqual(controller.midRestActivity.value, .free)
        render(21.9)
        XCTAssertEqual(controller.stage.value, .midRest)
        render(22)
        XCTAssertEqual(controller.stage.value, .fadingOut)
        controller.render(nil)
        controller.render(nil)
        XCTAssertEqual(controller.stage.value, .idle)
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(stops, 1)
    }

    func testCancelAndSnoozeAreAvailableThroughoutRestAndOnlyForwardActions() {
        var cancellations = 0
        var snoozes: [TimeInterval] = []
        let controller = RestController(onCancel: { cancellations += 1 },
                                        onSnooze: { snoozes.append($0) },
                                        onStartSound: {}, onStopSound: {})
        let id = UUID()
        for elapsed: TimeInterval in [0, 10, 22.5] {
            controller.render(.init(id: id, duration: 20, elapsed: elapsed,
                                    fadeInDuration: 2, fadeOutDuration: 1))
            controller.snooze(by: 120)
            controller.cancelRest()
        }
        XCTAssertEqual(cancellations, 3)
        XCTAssertEqual(snoozes, [120, 120, 120])
        controller.render(nil)
        controller.cancelRest()
        controller.snooze(by: 120)
        XCTAssertEqual(cancellations, 3)
        XCTAssertEqual(snoozes.count, 3)
    }

    func testInterruptedRestDoesNotEmitCompletion() {
        let controller = RestController(onCancel: {}, onSnooze: { _ in },
                                        onStartSound: {}, onStopSound: {})
        var reasons: [RestEndReason] = []
        let subscription = controller.didFinish.sink { reasons.append($0) }
        controller.render(.init(id: UUID(), duration: 20, elapsed: 5,
                                fadeInDuration: 2, fadeOutDuration: 1))
        controller.render(nil)
        controller.publishEnd(.interrupted)
        XCTAssertEqual(reasons, [.interrupted])
        XCTAssertEqual(controller.stage.value, .idle)
        withExtendedLifetime(subscription) {}
    }
}
