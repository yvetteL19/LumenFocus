import XCTest
@testable import LumenFocus

final class AppStateTests: XCTestCase {
    private func snapshot(_ phase: CyclePhase, remaining: TimeInterval = 600) -> CycleSnapshot {
        CycleSnapshot(phase: phase, remaining: remaining, progress: 0.5,
                      nextReminderDate: Date(timeIntervalSince1970: 1_800_000_000),
                      pauseUntil: Date(timeIntervalSince1970: 1_800_001_000),
                      environment: .available, rest: nil)
    }

    func testStoppedProjectionIsExplicitAndCannotLookLikeWorking() {
        let state = AppState()
        XCTAssertEqual(state.currentPhase, .stopped)
        state.apply(snapshot(.stopped))
        XCTAssertEqual(state.currentPhase, .stopped)
        XCTAssertFalse(state.isWorking)
        XCTAssertFalse(state.isResting)
    }

    func testCompletionReceiptSurvivesHeartbeatButNotTheNextRest() {
        let state = AppState()
        state.apply(snapshot(.working))
        state.recordRestOutcome(.completed)
        state.apply(snapshot(.working, remaining: 599))
        XCTAssertEqual(state.lastRestOutcome, .completed)
        state.apply(snapshot(.resting, remaining: 20))
        XCTAssertNil(state.lastRestOutcome, "An old completion must not describe the new rest")
    }

    func testEarlyEndRemainsDistinctFromCompletion() {
        let state = AppState()
        state.apply(snapshot(.working))
        state.recordRestOutcome(.userCancelled)
        XCTAssertEqual(state.lastRestOutcome, .userCancelled)
        state.recordRestOutcome(.interrupted)
        XCTAssertNil(state.lastRestOutcome, "Sleep or interruption must not look like a completed break")
    }

    func testPauseAndSuspensionCannotRetainOrCreateACompletionReceipt() {
        for phase in [CyclePhase.stopped, .paused, .suspended, .resting] {
            let state = AppState()
            state.apply(snapshot(.working))
            state.recordRestOutcome(.completed)
            state.apply(snapshot(phase))
            XCTAssertNil(state.lastRestOutcome)
            state.recordRestOutcome(.completed)
            XCTAssertNil(state.lastRestOutcome)
        }
    }
}
