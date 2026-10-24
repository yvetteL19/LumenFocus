import AppKit
import XCTest
@testable import LumenFocus

final class RelaunchHandoffTests: XCTestCase {
    private func onMain(_ action: () -> Void) {
        if Thread.isMainThread { action() } else { DispatchQueue.main.sync(execute: action) }
    }

    func testReplacementWaitsForTheCorrectProcessAndStartsOnlyOnce() {
        onMain {
            let center = NotificationCenter()
            let handoff = RelaunchHandoff(center: center, isRunning: { _ in true },
                                         terminatedPID: { $0.userInfo?["pid"] as? Int32 })
            var starts = 0
            handoff.wait(for: 42) { starts += 1 }
            XCTAssertEqual(starts, 0, "No records or shortcuts may load while the old process runs")
            center.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil, userInfo: ["pid": Int32(99)])
            XCTAssertEqual(starts, 0)
            center.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil, userInfo: ["pid": Int32(42)])
            center.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil, userInfo: ["pid": Int32(42)])
            XCTAssertEqual(starts, 1)
        }
    }

    func testAlreadyExitedPredecessorDoesNotLeaveReplacementWaiting() {
        onMain {
            let center = NotificationCenter()
            var checks = 0
            let handoff = RelaunchHandoff(center: center, isRunning: { _ in checks += 1; return false },
                                         terminatedPID: { $0.userInfo?["pid"] as? Int32 })
            var starts = 0
            handoff.wait(for: 42) { starts += 1 }
            center.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil, userInfo: ["pid": Int32(42)])
            XCTAssertEqual(checks, 1)
            XCTAssertEqual(starts, 1)
        }
    }

    func testCancellingReplacementRemovesObserverWithoutStartingRuntime() {
        onMain {
            let center = NotificationCenter()
            var starts = 0
            var handoff: RelaunchHandoff? = RelaunchHandoff(center: center, isRunning: { _ in true },
                                                          terminatedPID: { $0.userInfo?["pid"] as? Int32 })
            handoff?.wait(for: 42) { starts += 1 }
            handoff = nil
            center.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil, userInfo: ["pid": Int32(42)])
            XCTAssertEqual(starts, 0)
        }
    }

    func testExitBetweenSubscriptionAndLivenessCheckStillStartsOnlyOnce() {
        onMain {
            let center = NotificationCenter()
            let handoff = RelaunchHandoff(center: center, isRunning: { pid in
                center.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil, userInfo: ["pid": pid])
                return false
            }, terminatedPID: { $0.userInfo?["pid"] as? Int32 })
            var starts = 0
            handoff.wait(for: 42) { starts += 1 }
            XCTAssertEqual(starts, 1)
        }
    }
}
