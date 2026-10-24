import XCTest
@testable import LumenFocus

final class TestCycleClock: CycleClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    var elapsed: TimeInterval = 0

    func advance(_ seconds: TimeInterval) {
        elapsed += seconds
        now = now.addingTimeInterval(seconds)
    }
}

final class CycleEngineTests: XCTestCase {
    private func makeEngine(_ clock: TestCycleClock, work: TimeInterval = 2400) -> CycleEngine {
        CycleEngine(clock: clock, configuration: .init(workDuration: work, restDuration: 20))
    }

    private func recordedWork(_ events: [CycleEvent]) -> TimeInterval {
        events.reduce(0) { total, event in
            if case .workRecorded(let from, let to) = event { return total + to.timeIntervalSince(from) }
            return total
        }
    }

    private func completedRests(_ events: [CycleEvent]) -> [UUID] {
        events.compactMap {
            if case .restEnded(let id, _, .completed) = $0 { return id }
            return nil
        }
    }

    func testDueTimeAlwaysStartsRestWithoutAnInvitation() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock, work: 60)
        engine.start()
        clock.advance(60)
        engine.tick()
        XCTAssertEqual(engine.snapshot.phase, .resting)
        XCTAssertEqual(engine.snapshot.rest?.elapsed, 0)
        XCTAssertEqual(recordedWork(engine.drainEvents()), 60)
    }

    func testDelayedHeartbeatUsesElapsedClockAndStartsFullRestWhenObserved() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock)
        engine.start()
        clock.advance(123.5)
        clock.now = clock.now.addingTimeInterval(3 * 3600)
        engine.tick()
        XCTAssertEqual(engine.snapshot.remaining, 2276.5, accuracy: 0.001)
        XCTAssertEqual(recordedWork(engine.drainEvents()), 123.5, accuracy: 0.001)
        clock.advance(3000)
        engine.tick()
        XCTAssertEqual(engine.snapshot.phase, .resting)
        XCTAssertEqual(engine.snapshot.rest?.elapsed, 0, "A late tick must not consume unseen rest time")
        XCTAssertEqual(engine.snapshot.remaining, 20)
    }

    func testManualRestCannotEnableStoppedRemindersOrEndPause() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock)
        engine.beginRest()
        XCTAssertEqual(engine.snapshot.phase, .stopped)
        engine.start()
        let until = clock.now.addingTimeInterval(3600)
        engine.pause(until: until)
        engine.beginRest()
        XCTAssertEqual(engine.snapshot.phase, .paused)
        XCTAssertEqual(engine.snapshot.pauseUntil, until)
        XCTAssertNil(engine.snapshot.rest)
    }

    func testImmediateRestUsesNewSettingsBeforePreferenceObserverDelivery() {
        let clock = TestCycleClock()
        let engine = CycleEngine(clock: clock, configuration: .init(workDuration: 2400, restDuration: 300))
        engine.start()
        engine.beginRest(using: .init(workDuration: 1200, restDuration: 20))
        XCTAssertEqual(engine.snapshot.rest?.duration, 20)
        clock.advance(23)
        engine.tick()
        XCTAssertEqual(engine.snapshot.phase, .working)
        XCTAssertEqual(engine.snapshot.remaining, 1200)
        XCTAssertEqual(completedRests(engine.drainEvents()).count, 1)
    }

    func testCancelAndSkipEachStartAFullIntervalWithoutCompletion() {
        for elapsed: TimeInterval in [1, 10, 22.5] {
            let clock = TestCycleClock()
            let engine = makeEngine(clock)
            engine.start()
            clock.advance(2390)
            engine.beginRest()
            clock.advance(elapsed)
            engine.cancelRest()
            XCTAssertEqual(engine.snapshot.phase, .working)
            XCTAssertEqual(engine.snapshot.remaining, 2400)
            XCTAssertTrue(completedRests(engine.drainEvents()).isEmpty)
            clock.advance(300)
            engine.skipReminder()
            XCTAssertEqual(engine.snapshot.remaining, 2400)
            XCTAssertTrue(completedRests(engine.drainEvents()).isEmpty)
        }
    }

    func testSkipActiveRestStartsFullInterval() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock, work: 60)
        engine.start()
        clock.advance(60)
        engine.tick()
        engine.skipReminder()
        XCTAssertEqual(engine.snapshot.phase, .working)
        XCTAssertEqual(engine.snapshot.remaining, 60)
        XCTAssertTrue(completedRests(engine.drainEvents()).isEmpty)
    }

    func testPauseExpiryAndManualResumeStartFullInterval() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock, work: 60)
        engine.start()
        let until = clock.now.addingTimeInterval(300)
        engine.pause(until: until)
        clock.advance(300)
        engine.tick()
        XCTAssertEqual(engine.snapshot.phase, .working)
        XCTAssertEqual(engine.snapshot.remaining, 60)
        XCTAssertNil(engine.snapshot.pauseUntil)
        let events = engine.drainEvents()
        XCTAssertTrue(events.contains(.pauseExpired(until: until)))
        XCTAssertEqual(recordedWork(events), 300, "Pause suppresses reminders, not measured work")
        engine.pause(until: clock.now.addingTimeInterval(300))
        clock.advance(50)
        engine.resume()
        XCTAssertEqual(engine.snapshot.remaining, 60)
        XCTAssertNil(engine.snapshot.pauseUntil)
    }

    func testReplacingPauseCannotBeUndoneByOldDeadline() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock, work: 60)
        engine.start()
        engine.pause(until: clock.now.addingTimeInterval(100))
        clock.advance(20)
        let replacement = clock.now.addingTimeInterval(200)
        engine.pause(until: replacement)
        clock.advance(80)
        engine.tick()
        XCTAssertEqual(engine.snapshot.phase, .paused)
        XCTAssertEqual(engine.snapshot.pauseUntil, replacement)
        clock.advance(120)
        engine.tick()
        XCTAssertEqual(engine.snapshot.phase, .working)
        XCTAssertEqual(engine.snapshot.remaining, 60)
    }

    func testManualResumeAfterLateHeartbeatStillStartsFullInterval() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock, work: 60)
        engine.start(pausedUntil: clock.now.addingTimeInterval(100))
        clock.advance(200)
        engine.resume()
        XCTAssertEqual(engine.snapshot.phase, .working)
        XCTAssertEqual(engine.snapshot.remaining, 60)
        XCTAssertNil(engine.snapshot.pauseUntil)
    }

    func testRelaunchRestoresFuturePauseAndNeverCountsOfflineWork() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock, work: 60)
        let until = clock.now.addingTimeInterval(3600)
        engine.start(pausedUntil: until)
        clock.advance(10)
        engine.stop()
        XCTAssertEqual(recordedWork(engine.drainEvents()), 10)
        clock.advance(1800)
        let relaunched = makeEngine(clock, work: 60)
        relaunched.start(pausedUntil: until)
        XCTAssertEqual(relaunched.snapshot.phase, .paused)
        XCTAssertEqual(relaunched.snapshot.pauseUntil, until)
        XCTAssertTrue(relaunched.drainEvents().isEmpty)
        clock.advance(1790)
        relaunched.tick()
        XCTAssertEqual(relaunched.snapshot.phase, .working)
        XCTAssertEqual(relaunched.snapshot.remaining, 60)
        XCTAssertEqual(recordedWork(relaunched.drainEvents()), 1790)
    }

    func testExpiredPauseAtLaunchStartsFreshInsteadOfImmediatelyDimming() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock, work: 60)
        engine.start(pausedUntil: clock.now.addingTimeInterval(-300))
        XCTAssertEqual(engine.snapshot.phase, .working)
        XCTAssertNil(engine.snapshot.pauseUntil)
        XCTAssertEqual(engine.snapshot.remaining, 60)
    }

    func testPauseExpiryIsObservableDuringWakeAndDoesNotOverridePhysicalSleep() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock, work: 60)
        let until = clock.now.addingTimeInterval(100)
        engine.start(pausedUntil: until)
        engine.setEnvironment(.init(reason: .screenLocked, detail: nil, isAway: true))
        clock.advance(300)
        engine.setEnvironment(.available)
        XCTAssertEqual(engine.snapshot.phase, .working)
        XCTAssertEqual(engine.snapshot.remaining, 60)
        let events = engine.drainEvents()
        XCTAssertTrue(events.contains(.pauseExpired(until: until)))
        XCTAssertEqual(recordedWork(events), 0)
    }

    func testSleepCannotOverrideOngoingManualPause() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock)
        let until = clock.now.addingTimeInterval(3600)
        engine.start(pausedUntil: until)
        engine.setEnvironment(.init(reason: .screenLocked, detail: nil, isAway: true))
        clock.advance(120)
        engine.setEnvironment(.available)
        XCTAssertEqual(engine.snapshot.phase, .paused)
        XCTAssertEqual(engine.snapshot.pauseUntil, until)
    }

    func testSleepDuringRestWithdrawsItAndNaturalBreakIsNotGuidedCompletion() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock)
        engine.start()
        engine.beginRest()
        clock.advance(10)
        engine.setEnvironment(.init(reason: .screenLocked, detail: nil, isAway: true))
        XCTAssertNil(engine.snapshot.rest)
        XCTAssertEqual(engine.snapshot.phase, .suspended)
        clock.advance(3600)
        engine.tick()
        engine.setEnvironment(.available)
        XCTAssertEqual(engine.snapshot.phase, .working)
        XCTAssertEqual(engine.snapshot.remaining, 2400)
        let events = engine.drainEvents()
        XCTAssertTrue(completedRests(events).isEmpty)
        XCTAssertEqual(recordedWork(events), 0)
        XCTAssertTrue(events.contains(.naturalBreak(duration: 3600)))
    }

    func testShortSleepKeepsDueTimeWithRecoveryGrace() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock)
        engine.start()
        clock.advance(2390)
        engine.tick()
        engine.setEnvironment(.init(reason: .screenLocked, detail: nil, isAway: true))
        clock.advance(5)
        engine.setEnvironment(.available)
        XCTAssertEqual(engine.snapshot.remaining, 60)
        XCTAssertNil(engine.snapshot.rest)
        clock.advance(60)
        engine.tick()
        XCTAssertEqual(engine.snapshot.phase, .resting)
    }

    func testTwentySecondRestHasIndependentTransitionsAndOneCompletion() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock)
        engine.start()
        engine.beginRest()
        let id = engine.snapshot.rest?.id
        clock.advance(2)
        engine.tick()
        XCTAssertEqual(engine.snapshot.remaining, 20)
        clock.advance(19)
        engine.tick()
        XCTAssertEqual(engine.snapshot.remaining, 1)
        clock.advance(1)
        engine.tick()
        XCTAssertEqual(engine.snapshot.phase, .resting)
        XCTAssertEqual(engine.snapshot.remaining, 0)
        XCTAssertTrue(completedRests(engine.drainEvents()).isEmpty)
        clock.advance(1)
        engine.tick()
        engine.tick()
        XCTAssertEqual(engine.snapshot.phase, .working)
        XCTAssertEqual(completedRests(engine.drainEvents()), [id!])
    }

    func testActiveRestKeepsItsDurationWhenSettingsChange() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock)
        engine.start()
        engine.beginRest()
        clock.advance(10)
        engine.configure(.init(workDuration: 1200, restDuration: 300))
        XCTAssertEqual(engine.snapshot.rest?.duration, 20)
        clock.advance(13)
        engine.tick()
        XCTAssertEqual(engine.snapshot.phase, .working)
        XCTAssertEqual(engine.snapshot.remaining, 1200)
    }

    func testRuntimeConfigurationPreservesElapsedWork() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock)
        engine.start()
        clock.advance(1000)
        engine.configure(.init(workDuration: 1200, restDuration: 20))
        XCTAssertEqual(engine.snapshot.remaining, 200)
    }

    func testCalendarClockRollbackCannotExtendRestOrPause() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock)
        engine.start()
        engine.pause(until: clock.now.addingTimeInterval(100))
        clock.now = clock.now.addingTimeInterval(-3600)
        clock.advance(100)
        engine.tick()
        XCTAssertEqual(engine.snapshot.phase, .working)
        XCTAssertEqual(engine.snapshot.remaining, 2400)
        engine.beginRest()
        clock.advance(10)
        clock.now = clock.now.addingTimeInterval(-3600)
        engine.tick()
        XCTAssertEqual(engine.snapshot.remaining, 12)
        clock.advance(13)
        engine.tick()
        XCTAssertEqual(completedRests(engine.drainEvents()).count, 1)
    }

    func testStoppedEngineNeverCountsOfflineTimeOrResurrectsPause() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock)
        engine.start()
        engine.pause(until: clock.now.addingTimeInterval(100))
        clock.advance(10)
        engine.stop()
        XCTAssertEqual(recordedWork(engine.drainEvents()), 10)
        XCTAssertEqual(engine.snapshot.phase, .stopped)
        XCTAssertNil(engine.snapshot.pauseUntil)
        clock.advance(3600)
        engine.tick()
        XCTAssertTrue(engine.drainEvents().isEmpty)
        XCTAssertEqual(engine.snapshot.phase, .stopped)
        engine.start()
        XCTAssertEqual(engine.snapshot.remaining, 2400)
        XCTAssertTrue(engine.drainEvents().isEmpty)
    }
}
