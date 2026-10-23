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
    func testManualBreakFromPauseResumesCadenceAfterCompletion() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock)
        engine.start()
        engine.pause(until: clock.now.addingTimeInterval(3600))
        clock.advance(120)

        engine.beginRest()
        XCTAssertEqual(engine.snapshot.phase, .resting)
        XCTAssertNil(engine.snapshot.pauseUntil)
        clock.advance(23)
        engine.tick()

        XCTAssertEqual(engine.snapshot.phase, .working)
        XCTAssertEqual(engine.snapshot.remaining, 2400)
        XCTAssertEqual(completedRests(engine.drainEvents()).count, 1)
        clock.advance(2400)
        engine.tick()
        XCTAssertEqual(engine.snapshot.phase, .reminderDue, "Starting a break explicitly ends the old pause")
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

    private func makeEngine(_ clock: TestCycleClock, work: TimeInterval = 2400,
                            immersive: Bool = false) -> CycleEngine {
        CycleEngine(clock: clock, configuration: .init(workDuration: work, restDuration: 20,
                                                        automaticallyStartsRest: immersive))
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

    func testDelayedHeartbeatUsesDeadlineAndCalendarClockChangesDoNotChangeDuration() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock)
        engine.start()
        clock.advance(123.5)
        clock.now = clock.now.addingTimeInterval(3 * 3600)
        engine.tick()
        XCTAssertEqual(engine.snapshot.remaining, 2276.5, accuracy: 0.001)
        XCTAssertEqual(recordedWork(engine.drainEvents()), 123.5, accuracy: 0.001)
        clock.advance(2276.5)
        engine.tick()
        XCTAssertEqual(engine.snapshot.phase, .reminderDue)
        XCTAssertNil(engine.snapshot.rest)
    }

    func testSnoozeExtendsUpcomingDeadlineAndUsesNowWhenAlreadyDue() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock)
        engine.start()
        clock.advance(100)
        engine.snooze(by: 300)
        XCTAssertEqual(engine.snapshot.remaining, 2600)
        clock.advance(2600)
        engine.tick()
        XCTAssertEqual(engine.snapshot.phase, .reminderDue)
        engine.snooze(by: 300)
        XCTAssertEqual(engine.snapshot.remaining, 300)
        clock.advance(299)
        engine.tick()
        XCTAssertEqual(engine.snapshot.phase, .snoozed)
        clock.advance(1)
        engine.tick()
        XCTAssertEqual(engine.snapshot.phase, .reminderDue)
    }

    func testSnoozeUsesGraceDeadlineSoItCannotMoveReminderEarlier() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock, work: 60)
        engine.start()
        engine.setEnvironment(.init(reason: .videoCall, detail: "Meeting app", isAway: false))
        clock.advance(120)
        engine.setEnvironment(.available)
        XCTAssertEqual(engine.snapshot.remaining, 60)
        engine.snooze(by: 300)
        XCTAssertEqual(engine.snapshot.remaining, 360)
    }

    func testReplacingManualPauseCannotBeUndoneByOldDeadlineOrMeetingEnd() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock, work: 60)
        engine.start()
        engine.pause(until: clock.now.addingTimeInterval(100))
        clock.advance(20)
        engine.resume()
        engine.pause(until: clock.now.addingTimeInterval(200))
        clock.advance(80)
        engine.tick()
        XCTAssertEqual(engine.snapshot.phase, .paused, "The original 100-second pause must not resume this newer pause")
        engine.setEnvironment(.init(reason: .videoCall, detail: nil, isAway: false))
        engine.setEnvironment(.available)
        XCTAssertEqual(engine.snapshot.phase, .paused, "A meeting ending cannot override a manual pause")
        engine.setEnvironment(.init(reason: .videoCall, detail: nil, isAway: false))
        clock.advance(120)
        engine.tick()
        XCTAssertEqual(engine.snapshot.phase, .suspended, "Pause expiry cannot override a continuing meeting")
        engine.setEnvironment(.available)
        XCTAssertEqual(engine.snapshot.remaining, 60)
        clock.advance(60)
        engine.tick()
        XCTAssertEqual(engine.snapshot.phase, .reminderDue)
    }

    func testMeetingCountsWorkDoesNotBecomeNaturalBreakAndEndsWithGrace() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock, work: 60)
        engine.start()
        engine.setEnvironment(.init(reason: .videoCall, detail: "Meeting app", isAway: false))
        clock.advance(7200)
        engine.tick()
        XCTAssertEqual(engine.snapshot.phase, .suspended)
        let events = engine.drainEvents()
        XCTAssertEqual(recordedWork(events), 7200)
        XCTAssertFalse(events.contains { if case .naturalBreak = $0 { return true }; return false })
        engine.setEnvironment(.available)
        XCTAssertEqual(engine.snapshot.phase, .working)
        XCTAssertEqual(engine.snapshot.remaining, 60)
        clock.advance(59)
        engine.tick()
        XCTAssertEqual(engine.snapshot.remaining, 1)
        clock.advance(1)
        engine.tick()
        XCTAssertEqual(engine.snapshot.phase, .reminderDue)
    }

    func testReadingWithoutInputDowngradesImmersiveModeAndDoesNotResetCycle() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock, work: 60, immersive: true)
        engine.start()
        engine.setEnvironment(.init(reason: .idle, detail: nil, isAway: false))
        clock.advance(180)
        engine.tick()
        XCTAssertEqual(engine.snapshot.phase, .reminderDue)
        XCTAssertNil(engine.snapshot.rest)
        XCTAssertEqual(recordedWork(engine.drainEvents()), 180)
        engine.setEnvironment(.available)
        engine.tick()
        XCTAssertEqual(engine.snapshot.phase, .reminderDue, "Typing again must not convert an existing invitation to an overlay")
        engine.beginRest()
        XCTAssertEqual(engine.snapshot.phase, .resting)
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
        XCTAssertTrue(events.contains { if case .restEnded(_, _, .interrupted) = $0 { return true }; return false })
    }

    func testShortSleepKeepsDueTimeAndAllowsGraceInsteadOfRestartingFullCycle() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock)
        engine.start()
        clock.advance(2390)
        engine.beginRest()
        engine.setEnvironment(.init(reason: .screenLocked, detail: nil, isAway: true))
        clock.advance(5)
        engine.setEnvironment(.available)
        XCTAssertEqual(engine.snapshot.remaining, 60)
        XCTAssertTrue(completedRests(engine.drainEvents()).isEmpty)
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

    func testCancelRestPreservesDueAndFiveMinuteGraceWhileSkipStartsNewCycle() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock)
        engine.start()
        clock.advance(2390)
        engine.beginRest()
        clock.advance(5)
        engine.cancelRest()
        XCTAssertEqual(engine.snapshot.remaining, 300)
        XCTAssertTrue(completedRests(engine.drainEvents()).isEmpty)
        engine.skipReminder()
        XCTAssertEqual(engine.snapshot.remaining, 2400)
    }

    func testRestCanBeSnoozedFromEveryPhaseWithoutCompletion() {
        for elapsed: TimeInterval in [1, 10, 22.5] {
            let clock = TestCycleClock()
            let engine = makeEngine(clock)
            engine.start()
            engine.beginRest()
            clock.advance(elapsed)
            engine.snooze(by: 120)
            XCTAssertNil(engine.snapshot.rest)
            XCTAssertEqual(engine.snapshot.remaining, 120)
            XCTAssertTrue(completedRests(engine.drainEvents()).isEmpty)
        }
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

    func testRuntimeConfigurationPreservesElapsedWorkAndExplicitSnooze() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock)
        engine.start()
        clock.advance(1000)
        engine.configure(.init(workDuration: 1200, restDuration: 20))
        XCTAssertEqual(engine.snapshot.remaining, 200)
        engine.snooze(by: 300)
        XCTAssertEqual(engine.snapshot.remaining, 500)
        engine.configure(.init(workDuration: 2400, restDuration: 60))
        XCTAssertEqual(engine.snapshot.remaining, 500, "A settings edit must not rewrite an explicit snooze")
    }

    func testEnvironmentRecoveryCannotShortenAnExistingCancellationGrace() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock, work: 60)
        engine.start()
        clock.advance(60)
        engine.beginRest()
        clock.advance(5)
        engine.cancelRest()
        XCTAssertEqual(engine.snapshot.remaining, 300)
        engine.setEnvironment(.init(reason: .videoCall, detail: nil, isAway: false))
        clock.advance(10)
        engine.setEnvironment(.available)
        XCTAssertEqual(engine.snapshot.remaining, 290)
    }

    func testMovingCalendarClockBackwardsDoesNotExtendRunningRest() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock)
        engine.start()
        engine.beginRest()
        clock.advance(10)
        clock.now = clock.now.addingTimeInterval(-3600)
        engine.tick()
        XCTAssertEqual(engine.snapshot.remaining, 12)
        clock.advance(13)
        engine.tick()
        XCTAssertEqual(engine.snapshot.phase, .working)
        XCTAssertEqual(completedRests(engine.drainEvents()).count, 1)
    }

    func testStoppedOrRestartedEngineNeverCountsOfflineTime() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock)
        engine.start()
        clock.advance(10)
        engine.stop()
        XCTAssertEqual(recordedWork(engine.drainEvents()), 10)
        clock.advance(3600)
        engine.tick()
        XCTAssertTrue(engine.drainEvents().isEmpty)
        let restarted = makeEngine(clock)
        restarted.start()
        XCTAssertEqual(restarted.snapshot.remaining, 2400)
        XCTAssertTrue(restarted.drainEvents().isEmpty)
    }

    func testSwitchingEnvironmentOffRestoresGraceWithoutLosingManualPause() {
        let clock = TestCycleClock()
        let engine = makeEngine(clock, work: 60)
        engine.start()
        engine.pause(until: clock.now.addingTimeInterval(300))
        engine.setEnvironment(.init(reason: .fullscreen, detail: nil, isAway: false))
        clock.advance(120)
        engine.setEnvironment(.available)
        XCTAssertEqual(engine.snapshot.phase, .paused)
        engine.resume()
        XCTAssertEqual(engine.snapshot.phase, .working)
        XCTAssertEqual(engine.snapshot.remaining, 60)
    }
}

final class WorkspaceRuleResolverTests: XCTestCase {
    private let ownID = "example.LumenFocus.tests"

    func testRuleAppRemainsSuppressedWhileOwnPopoverOrSettingsIsFrontmost() {
        var resolver = ForegroundAppRuleResolver()
        let zoom = resolver.resolve(bundleID: "us.zoom.xos", name: "Zoom", ownBundleID: ownID,
                                    enabled: true, videoCall: true, fullscreen: true)
        XCTAssertEqual(zoom, PauseSignal(reason: .videoCall, detail: "Zoom"))
        let own = resolver.resolve(bundleID: ownID, name: "LumenFocus", ownBundleID: ownID,
                                   enabled: true, videoCall: true, fullscreen: true)
        XCTAssertEqual(own, zoom)
        let editor = resolver.resolve(bundleID: "com.apple.dt.Xcode", name: "Xcode", ownBundleID: ownID,
                                      enabled: true, videoCall: true, fullscreen: true)
        XCTAssertNil(editor)
        XCTAssertNil(resolver.resolve(bundleID: ownID, name: "LumenFocus", ownBundleID: ownID,
                                      enabled: true, videoCall: true, fullscreen: true))
    }

    func testMasterAndRuleSwitchesApplyWhileOwnSettingsWindowRemainsFrontmost() {
        var resolver = ForegroundAppRuleResolver()
        _ = resolver.resolve(bundleID: "us.zoom.xos", name: "Zoom", ownBundleID: ownID,
                             enabled: true, videoCall: true, fullscreen: true)
        XCTAssertNil(resolver.resolve(bundleID: ownID, name: nil, ownBundleID: ownID,
                                      enabled: false, videoCall: true, fullscreen: true))
        XCTAssertNil(resolver.resolve(bundleID: ownID, name: nil, ownBundleID: ownID,
                                      enabled: true, videoCall: false, fullscreen: true))
        XCTAssertEqual(resolver.resolve(bundleID: ownID, name: nil, ownBundleID: ownID,
                                        enabled: true, videoCall: true, fullscreen: true)?.reason, .videoCall)
    }

    func testPresentationRuleRetainsExternalContextWithoutClaimingRealFullscreenDetection() {
        var resolver = ForegroundAppRuleResolver()
        _ = resolver.resolve(bundleID: "com.apple.iWork.Keynote", name: "Keynote", ownBundleID: ownID,
                             enabled: true, videoCall: true, fullscreen: true)
        let own = resolver.resolve(bundleID: ownID, name: "LumenFocus", ownBundleID: ownID,
                                   enabled: true, videoCall: true, fullscreen: true)
        XCTAssertEqual(own, PauseSignal(reason: .fullscreen, detail: "Keynote"))
        XCTAssertNil(resolver.resolve(bundleID: ownID, name: nil, ownBundleID: ownID,
                                      enabled: true, videoCall: true, fullscreen: false))
    }

    func testOwnAppWithNoExternalContextDoesNotInventMeetingState() {
        var resolver = ForegroundAppRuleResolver()
        XCTAssertNil(resolver.resolve(bundleID: ownID, name: "LumenFocus", ownBundleID: ownID,
                                      enabled: true, videoCall: true, fullscreen: true))
    }
}
