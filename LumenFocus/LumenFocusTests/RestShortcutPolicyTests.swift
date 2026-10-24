import XCTest
@testable import LumenFocus

final class RestShortcutPolicyTests: XCTestCase {
    func testModifierExitThenCarbonPressCannotReopenTheRest() {
        var policy = RestShortcutPolicy()
        policy.restDidEnd(at: 10)
        XCTAssertEqual(policy.pressed(isResting: false, at: 10.1), .ignore)
        XCTAssertEqual(policy.pressed(isResting: false, at: 12), .ignore, "Holding the same gesture must stay ignored")
        policy.released()
        XCTAssertEqual(policy.pressed(isResting: false, at: 12.1), .start)
    }

    func testAReleasedShortcutCanStartAgainWithoutWaitingOneSecond() {
        var policy = RestShortcutPolicy()
        policy.restDidEnd(at: 10)
        XCTAssertEqual(policy.pressed(isResting: false, at: 10.1), .ignore)
        policy.released()
        XCTAssertEqual(policy.pressed(isResting: false, at: 10.2), .start)
    }

    func testShortcutDuringRestCancelsOnlyOnce() {
        var policy = RestShortcutPolicy()
        XCTAssertEqual(policy.pressed(isResting: true, at: 10), .cancel)
        policy.restDidEnd(at: 10)
        XCTAssertEqual(policy.pressed(isResting: false, at: 10.2), .ignore)
        XCTAssertEqual(policy.pressed(isResting: false, at: 20), .ignore)
        policy.released()
        XCTAssertEqual(policy.pressed(isResting: false, at: 20.1), .start)
    }

    func testHeldStartShortcutCannotImmediatelyCancelNewRest() {
        var policy = RestShortcutPolicy()
        XCTAssertEqual(policy.pressed(isResting: false, at: 10), .start)
        XCTAssertEqual(policy.pressed(isResting: true, at: 10.1), .ignore)
        policy.released()
        XCTAssertEqual(policy.pressed(isResting: true, at: 10.2), .cancel)
    }

    func testOrdinaryKeyCancellationHasOnlyABoundedShortcutCooldown() {
        var policy = RestShortcutPolicy()
        policy.restDidEnd(at: 10)
        XCTAssertEqual(policy.pressed(isResting: false, at: 11), .start)
    }
}
