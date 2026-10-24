import XCTest
import Combine
@testable import LumenFocus

/// Tests only the presentation adapter; no global timer, sound, or user defaults are touched.
final class RestControllerStateMachineTests: XCTestCase {
    func testStagesGiveTwentySecondsToActualRestAndDefaultToLookingAway() {
        let controller = RestController(onCancel: {})
        let id = UUID()
        func render(_ elapsed: TimeInterval) {
            controller.render(.init(id: id, duration: 20, elapsed: elapsed,
                                    fadeInDuration: 2, fadeOutDuration: 1))
        }
        render(0)
        XCTAssertEqual(controller.stage.value, .fadingIn)
        render(2)
        XCTAssertEqual(controller.stage.value, .midRest)
        render(21.9)
        XCTAssertEqual(controller.stage.value, .midRest)
        render(22)
        XCTAssertEqual(controller.stage.value, .fadingOut)
        controller.render(nil)
        controller.render(nil)
        XCTAssertEqual(controller.stage.value, .idle)
    }

    func testCancelIsAvailableThroughoutRestAndOnlyForwardsActions() {
        var cancellations = 0
        let controller = RestController(onCancel: { cancellations += 1 })
        let id = UUID()
        for elapsed: TimeInterval in [0, 10, 22.5] {
            controller.render(.init(id: id, duration: 20, elapsed: elapsed,
                                    fadeInDuration: 2, fadeOutDuration: 1))
            controller.cancelRest()
        }
        XCTAssertEqual(cancellations, 3)
        controller.render(nil)
        controller.cancelRest()
        XCTAssertEqual(cancellations, 3)
    }

    func testInterruptedRestDoesNotEmitCompletion() {
        let controller = RestController(onCancel: {})
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
