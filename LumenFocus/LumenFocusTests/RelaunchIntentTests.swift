import AppKit
import XCTest
@testable import LumenFocus

final class RelaunchIntentTests: XCTestCase {
    private var directory: URL!
    private var date: Date!
    private let bundleID = "LumenFocus.RelaunchIntentTests"
    private var payloadURL: URL { directory.appendingPathComponent("relaunch-intent.json") }

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LumenFocus-relaunch-\(UUID().uuidString)")
        date = Date(timeIntervalSince1970: 1_792_843_200.875)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        date = nil
        super.tearDown()
    }

    private func store() -> RelaunchIntentStore {
        RelaunchIntentStore(directory: directory, now: { [unowned self] in self.date })
    }

    private func prepare(using store: RelaunchIntentStore? = nil) throws -> RelaunchIntent {
        try (store ?? self.store()).prepare(previousPID: 42, previousLaunchDate: date.addingTimeInterval(-120),
                                           bundleIdentifier: bundleID)
    }

    func testFreshStoreInstanceConsumesTheRequestExactlyOnce() throws {
        let expected = try prepare()
        date += 0.2
        XCTAssertEqual(store().consume(currentPID: 43, currentLaunchDate: date, bundleIdentifier: bundleID), expected)
        XCTAssertNil(store().consume(currentPID: 44, currentLaunchDate: date, bundleIdentifier: bundleID))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testOriginalAndPreviouslyLaunchedProcessesCannotStealTheRequest() throws {
        let expected = try prepare()
        XCTAssertNil(store().consume(currentPID: 42, currentLaunchDate: date, bundleIdentifier: bundleID))
        XCTAssertNil(store().consume(currentPID: 41, currentLaunchDate: date.addingTimeInterval(-2), bundleIdentifier: bundleID))
        XCTAssertEqual(store().consume(currentPID: 43, currentLaunchDate: date, bundleIdentifier: bundleID), expected)
    }

    func testLaunchDateRoundedToSameSecondDoesNotRejectTheReplacement() throws {
        let expected = try prepare()
        let roundedLaunchDate = Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
        date += 0.05
        XCTAssertEqual(store().consume(currentPID: 43, currentLaunchDate: roundedLaunchDate, bundleIdentifier: bundleID), expected)
    }

    func testExpiredRequestIsRemovedWithoutAffectingOrdinaryStartup() throws {
        _ = try prepare()
        date += RelaunchIntentStore.lifetime
        XCTAssertNil(store().consume(currentPID: 43, currentLaunchDate: date, bundleIdentifier: bundleID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: payloadURL.path))
        XCTAssertNil(store().consume(currentPID: 44, currentLaunchDate: date, bundleIdentifier: bundleID))
    }

    func testFutureDatedRequestIsRejectedAfterClockRollback() throws {
        _ = try prepare()
        date -= 1
        XCTAssertNil(store().consume(currentPID: 43, currentLaunchDate: date, bundleIdentifier: bundleID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: payloadURL.path))
    }

    func testDifferentBundleCannotUseTheRequest() throws {
        _ = try prepare()
        XCTAssertNil(store().consume(currentPID: 43, currentLaunchDate: date, bundleIdentifier: "LumenFocus.Other"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: payloadURL.path))
    }

    func testFailedAttemptCanBeRetriedAndOldTokenCannotCancelTheRetry() throws {
        let store = store()
        let failed = try prepare(using: store)
        store.cancel(token: failed.token)
        XCTAssertNil(store.consume(currentPID: 43, currentLaunchDate: date, bundleIdentifier: bundleID))
        let retry = try prepare(using: store)
        XCTAssertNotEqual(failed.token, retry.token)
        store.cancel(token: failed.token)
        XCTAssertEqual(store.consume(currentPID: 44, currentLaunchDate: date, bundleIdentifier: bundleID), retry)
    }

    func testCorruptAndUnreasonablyLargePayloadsAreDiscarded() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for payload in [Data("not JSON".utf8), Data(repeating: 0x20, count: 4097)] {
            try payload.write(to: payloadURL)
            XCTAssertNil(store().consume(currentPID: 43, currentLaunchDate: date, bundleIdentifier: bundleID))
            XCTAssertFalse(FileManager.default.fileExists(atPath: payloadURL.path))
        }
    }

    func testInvalidIdentityAndFailedStorageCannotCreateARequest() throws {
        let store = store()
        XCTAssertThrowsError(try store.prepare(previousPID: 0, previousLaunchDate: date, bundleIdentifier: bundleID))
        XCTAssertThrowsError(try store.prepare(previousPID: 42, previousLaunchDate: date.addingTimeInterval(1), bundleIdentifier: bundleID))
        XCTAssertThrowsError(try store.prepare(previousPID: 42, previousLaunchDate: date, bundleIdentifier: ""))
        XCTAssertFalse(FileManager.default.fileExists(atPath: payloadURL.path))
        try Data("file, not directory".utf8).write(to: directory)
        XCTAssertThrowsError(try prepare(using: store))
    }

    func testReusedPIDOrDifferentBundleDoesNotMatchThePredecessor() throws {
        let intent = try prepare()
        XCTAssertTrue(intent.matchesPredecessor(bundleIdentifier: bundleID, launchDate: intent.previousLaunchDate))
        XCTAssertFalse(intent.matchesPredecessor(bundleIdentifier: bundleID, launchDate: intent.previousLaunchDate.addingTimeInterval(1)))
        XCTAssertFalse(intent.matchesPredecessor(bundleIdentifier: "LumenFocus.Other", launchDate: intent.previousLaunchDate))
        XCTAssertFalse(intent.matchesPredecessor(bundleIdentifier: bundleID, launchDate: nil))
    }

    func testReplacementLoadsFinalSavedStatisticsOnlyAfterPredecessorExit() throws {
        let run = {
            let suiteName = "LumenFocus.RelaunchStatisticsTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defer { defaults.removePersistentDomain(forName: suiteName) }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let referenceDate = self.date!
            let oldRepository = StatisticsManager(defaults: defaults, calendar: calendar, now: { referenceDate })
            oldRepository.recordWork(from: referenceDate.addingTimeInterval(-10), to: referenceDate)
            let intent = try self.prepare()
            let consumed = try XCTUnwrap(self.store().consume(currentPID: 43, currentLaunchDate: referenceDate,
                                                              bundleIdentifier: self.bundleID))
            XCTAssertEqual(consumed, intent)
            let center = NotificationCenter()
            let handoff = RelaunchHandoff(center: center, isRunning: { _ in true },
                                         terminatedPID: { $0.userInfo?["pid"] as? Int32 })
            var replacement: StatisticsManager?
            handoff.wait(for: consumed.previousPID) {
                replacement = StatisticsManager(defaults: defaults, calendar: calendar, now: { referenceDate })
            }
            XCTAssertNil(replacement, "No replacement repository may load an old snapshot before final flush")
            oldRepository.flush()
            center.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil,
                        userInfo: ["pid": consumed.previousPID])
            let reopened = try XCTUnwrap(replacement)
            XCTAssertEqual(reopened.getTodayStatistics().workDuration, 10)
            reopened.recordWork(from: referenceDate, to: referenceDate.addingTimeInterval(5))
            reopened.flush()
            XCTAssertEqual(StatisticsManager(defaults: defaults, calendar: calendar, now: { referenceDate })
                .getTodayStatistics().workDuration, 15, "Further saves must retain the predecessor's final work")
        }
        if Thread.isMainThread { try run() } else { try DispatchQueue.main.sync(execute: run) }
    }
}
