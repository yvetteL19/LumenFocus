import XCTest
@testable import LumenFocus

final class StatisticsManagerTests: XCTestCase {
    private final class Clock {
        var date: Date
        init(_ date: Date) { self.date = date }
    }

    private final class CalendarSource {
        var calendar: Calendar

        init(_ timeZone: String) {
            calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: timeZone)!
        }

        func change(to timeZone: String) {
            calendar.timeZone = TimeZone(identifier: timeZone)!
        }
    }

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var calendar: Calendar!
    private var clock: Clock!

    override func setUp() {
        super.setUp()
        suiteName = "LumenFocus.StatisticsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        clock = Clock(date("2026-10-22T12:00:00Z"))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        clock = nil
        super.tearDown()
    }

    private func repository(retentionDays: Int = 90) -> StatisticsManager {
        let testClock = clock!
        return StatisticsManager(defaults: defaults, calendar: calendar,
                                 now: { testClock.date }, retentionDays: retentionDays)
    }

    private func repository(calendarSource: CalendarSource, retentionDays: Int = 90) -> StatisticsManager {
        let testClock = clock!
        return StatisticsManager(defaults: defaults, calendarProvider: { calendarSource.calendar },
                                 now: { testClock.date }, retentionDays: retentionDays)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func key(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func testCodableRoundtrip() throws {
        let stats = DailyStatistics(date: "2026-10-22", restCount: 7, workDuration: 2400)
        let decoded = try JSONDecoder().decode(DailyStatistics.self, from: JSONEncoder().encode(stats))
        XCTAssertEqual(decoded, stats)
    }

    func testMigrationTakesPerDayMaximumWithoutAddingOverlappingStores() throws {
        let old = [DailyStatistics(date: "2026-10-22", restCount: 4, workDuration: 80),
                   DailyStatistics(date: "2026-10-21", restCount: 1, workDuration: 10)]
        defaults.set(try JSONEncoder().encode(old), forKey: "dailyStatisticsData")
        defaults.set(6, forKey: "restCount_2026-10-22")
        defaults.set(40, forKey: "workDuration_2026-10-22")
        defaults.set(3, forKey: "restCount_2026-10-21")
        defaults.set(true, forKey: "hasMigratedToStatisticsManager")
        let manager = repository()

        XCTAssertEqual(manager.getTodayStatistics(), DailyStatistics(date: "2026-10-22", restCount: 6, workDuration: 80))
        XCTAssertEqual(manager.getAllStatistics().first?.restCount, 3)
        XCTAssertEqual(defaults.integer(forKey: "statisticsMigrationVersion"), 2)
        XCTAssertNil(defaults.object(forKey: "dailyStatisticsData"))
        XCTAssertNil(defaults.object(forKey: "restCount_2026-10-22"))
        XCTAssertNil(defaults.object(forKey: "workDuration_2026-10-22"))
        XCTAssertEqual(repository().getAllStatistics(), manager.getAllStatistics())
    }

    func testMidnightSplitsWorkIntoTheCorrectLocalDays() {
        clock.date = date("2026-10-22T00:00:02Z")
        let manager = repository()
        manager.recordWork(from: date("2026-10-21T23:59:58Z"), to: clock.date)

        XCTAssertEqual(manager.getAllStatistics(), [
            DailyStatistics(date: "2026-10-21", workDuration: 2),
            DailyStatistics(date: "2026-10-22", workDuration: 2)
        ])
    }

    func testSubsecondTicksAccumulateAndSurviveReload() {
        let manager = repository()
        let start = clock.date
        clock.date = start.addingTimeInterval(0.6)
        manager.recordWork(from: start, to: clock.date)
        manager.flush()
        let reloaded = repository()
        let nextStart = clock.date
        clock.date = nextStart.addingTimeInterval(0.6)
        reloaded.recordWork(from: nextStart, to: clock.date)
        XCTAssertEqual(reloaded.getTodayStatistics().workDuration, 1)
    }

    func testCompletedSessionIsIdempotentBeforeAndAfterReload() {
        let id = UUID()
        let manager = repository()
        manager.recordCompletedRest(at: clock.date, id: id)
        manager.recordCompletedRest(at: clock.date, id: id)
        XCTAssertEqual(manager.getTodayStatistics().restCount, 1)

        let reloaded = repository()
        reloaded.recordCompletedRest(at: clock.date, id: id)
        XCTAssertEqual(reloaded.getTodayStatistics().restCount, 1)
        reloaded.recordCompletedRest(at: clock.date, id: UUID())
        XCTAssertEqual(reloaded.getTodayStatistics().restCount, 2)
    }

    func testRetentionKeepsExactlyTodayAndPrevious89DaysOnMigration() throws {
        let today = calendar.startOfDay(for: clock.date)
        let oldestKept = calendar.date(byAdding: .day, value: -89, to: today)!
        let expired = calendar.date(byAdding: .day, value: -90, to: today)!
        defaults.set(try JSONEncoder().encode([
            DailyStatistics(date: key(expired), restCount: 8),
            DailyStatistics(date: key(oldestKept), restCount: 2),
            DailyStatistics(date: key(today), workDuration: 30)
        ]), forKey: "dailyStatisticsData")
        defaults.set(20, forKey: "restCount_\(key(expired))")

        let manager = repository()
        XCTAssertEqual(manager.getAllStatistics().map(\.date), [key(oldestKept), key(today)])
        XCTAssertNil(defaults.object(forKey: "restCount_\(key(expired))"))
        XCTAssertEqual(repository().getAllStatistics(), manager.getAllStatistics())
    }

    func testDayRolloverPrunesHistoryAndDoesNotCreateARecordedZeroDay() {
        let manager = repository(retentionDays: 2)
        manager.recordCompletedRest(at: clock.date, id: UUID())
        clock.date = calendar.date(byAdding: .day, value: 1, to: clock.date)!
        XCTAssertEqual(manager.refreshToday().restCount, 0)
        XCTAssertEqual(manager.getAllStatistics().count, 1)
        clock.date = calendar.date(byAdding: .day, value: 1, to: clock.date)!
        manager.refreshToday()
        XCTAssertTrue(manager.getAllStatistics().isEmpty)
        XCTAssertTrue(repository(retentionDays: 2).getAllStatistics().isEmpty)
    }

    func testMissingDaysAreAbsentAndWorkingDaysCountInTheAverage() {
        defaults.set(0, forKey: "restCount_2026-10-20")
        defaults.set(0, forKey: "workDuration_2026-10-20")
        let manager = repository()
        XCTAssertTrue(manager.getWeeklyStatistics().isEmpty)
        XCTAssertEqual(manager.getTodayStatistics().workDuration, 0)
        XCTAssertTrue(manager.getAllStatistics().isEmpty)
        manager.recordCompletedRest(at: clock.date, id: UUID())
        manager.recordCompletedRest(at: clock.date, id: UUID())
        let previous = calendar.date(byAdding: .day, value: -1, to: clock.date)!
        manager.recordWork(from: previous, to: previous.addingTimeInterval(20))
        XCTAssertEqual(manager.getWeeklyStatistics().count, 2)
        XCTAssertEqual(manager.getDailyAverageRestCount(), 1)
    }

    func testWorkTicksStayInMemoryUntilBatchFlush() throws {
        let manager = repository()
        let baseline = try XCTUnwrap(defaults.data(forKey: "statisticsStoreV2"))
        let start = clock.date
        for second in 0..<59 {
            let from = start.addingTimeInterval(Double(second))
            clock.date = from.addingTimeInterval(1)
            manager.recordWork(from: from, to: clock.date)
        }
        XCTAssertEqual(manager.getTodayStatistics().workDuration, 59)
        XCTAssertEqual(defaults.data(forKey: "statisticsStoreV2"), baseline)
        clock.date = start.addingTimeInterval(60)
        manager.recordWork(from: start.addingTimeInterval(59), to: clock.date)
        XCTAssertNotEqual(defaults.data(forKey: "statisticsStoreV2"), baseline)
        XCTAssertEqual(repository().getTodayStatistics().workDuration, 60)
    }

    func testInvalidOrExpiredIntervalsDoNotManufactureRecords() {
        let manager = repository()
        manager.recordWork(from: clock.date, to: clock.date)
        manager.recordWork(from: clock.date, to: clock.date.addingTimeInterval(-1))
        let expired = calendar.date(byAdding: .day, value: -100, to: clock.date)!
        manager.recordWork(from: expired, to: expired.addingTimeInterval(30))
        manager.recordCompletedRest(at: expired, id: UUID())
        XCTAssertTrue(manager.getAllStatistics().isEmpty)
    }

    func testDaylightSavingTimeCountsElapsedSecondsRatherThanWallClockHours() {
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        clock.date = date("2026-03-08T10:00:01Z")
        let manager = repository()
        manager.recordWork(from: date("2026-03-08T09:59:59Z"), to: clock.date)
        XCTAssertEqual(manager.getTodayStatistics(), DailyStatistics(date: "2026-03-08", workDuration: 2))
    }

    func testMovingClockBackPreservesHistoryAndCompletionIDs() {
        let manager = repository()
        let recordedDate = clock.date
        let sessionID = UUID()
        manager.recordCompletedRest(at: recordedDate, id: sessionID)
        clock.date = calendar.date(byAdding: .day, value: -1, to: clock.date)!
        XCTAssertEqual(manager.refreshToday().restCount, 0)
        XCTAssertTrue(manager.getWeeklyStatistics().isEmpty)
        XCTAssertEqual(manager.getAllStatistics().count, 1)

        let reloaded = repository()
        XCTAssertEqual(reloaded.getAllStatistics().count, 1)
        clock.date = recordedDate
        reloaded.recordCompletedRest(at: recordedDate, id: sessionID)
        XCTAssertEqual(reloaded.getTodayStatistics().restCount, 1)
    }

    func testUnreadableStoreIsBackedUpBeforeRecovery() throws {
        let unreadable = Data("unreadable-statistics-payload".utf8)
        defaults.set(unreadable, forKey: "statisticsStoreV2")
        defaults.set(3, forKey: "restCount_2026-10-22")
        let manager = repository()
        let recoveryKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("statisticsStoreV2.recovery.") }
        XCTAssertEqual(recoveryKeys.count, 1)
        XCTAssertEqual(defaults.data(forKey: try XCTUnwrap(recoveryKeys.first)), unreadable)
        XCTAssertEqual(manager.getTodayStatistics().restCount, 3)
        XCTAssertEqual(repository().getTodayStatistics().restCount, 3)
    }

    func testUnreadableLegacyPayloadIsAlsoPreserved() throws {
        let unreadable = Data("unreadable-legacy-payload".utf8)
        defaults.set(unreadable, forKey: "dailyStatisticsData")
        let manager = repository()
        let recoveryKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("statisticsLegacy.recovery.") }
        XCTAssertEqual(recoveryKeys.count, 1)
        XCTAssertEqual(defaults.data(forKey: try XCTUnwrap(recoveryKeys.first)), unreadable)
        XCTAssertTrue(manager.getAllStatistics().isEmpty)
    }

    func testEastwardTimeZoneChangeSplitsPendingWorkWithoutRelabelingHistory() {
        let source = CalendarSource("UTC")
        clock.date = date("2026-10-22T15:59:58Z")
        let manager = repository(calendarSource: source)
        let start = clock.date
        manager.recordCompletedRest(at: start, id: UUID())

        clock.date = date("2026-10-22T16:00:00Z")
        source.change(to: "Asia/Shanghai")
        XCTAssertEqual(manager.refreshToday(), DailyStatistics(date: "2026-10-23"))
        clock.date = date("2026-10-22T16:00:02Z")
        manager.recordWork(from: start, to: clock.date)

        XCTAssertEqual(manager.getAllStatistics(), [
            DailyStatistics(date: "2026-10-22", restCount: 1, workDuration: 2),
            DailyStatistics(date: "2026-10-23", workDuration: 2)
        ])
        XCTAssertEqual(manager.getTodayStatistics().workDuration, 2)
    }

    func testWestwardChangeSplitsPendingWorkAcrossOldMidnightAndPreservesFutureDay() {
        let source = CalendarSource("Asia/Shanghai")
        clock.date = date("2026-10-22T15:59:58Z")
        let manager = repository(calendarSource: source)
        let start = clock.date
        clock.date = date("2026-10-22T16:00:01Z")
        source.change(to: "America/Los_Angeles")
        manager.refreshToday()
        clock.date = date("2026-10-22T16:00:03Z")
        manager.recordWork(from: start, to: clock.date)
        manager.flush()

        XCTAssertEqual(manager.getAllStatistics(), [
            DailyStatistics(date: "2026-10-22", workDuration: 4),
            DailyStatistics(date: "2026-10-23", workDuration: 1)
        ])
        XCTAssertEqual(manager.getWeeklyStatistics(), [DailyStatistics(date: "2026-10-22", workDuration: 4)])
        XCTAssertEqual(repository(calendarSource: source).getAllStatistics(), manager.getAllStatistics())
    }

    func testWorkAfterSwitchSplitsAtTheNewTimeZonesMidnight() {
        let source = CalendarSource("UTC")
        clock.date = date("2026-10-22T15:59:58Z")
        let manager = repository(calendarSource: source)
        source.change(to: "Asia/Shanghai")
        manager.refreshToday()
        let start = clock.date
        clock.date = date("2026-10-22T16:00:02Z")
        manager.recordWork(from: start, to: clock.date)

        XCTAssertEqual(manager.getAllStatistics(), [
            DailyStatistics(date: "2026-10-22", workDuration: 2),
            DailyStatistics(date: "2026-10-23", workDuration: 2)
        ])
    }

    func testChangeFirstObservedByWorkUsesObservationAsBoundary() {
        let source = CalendarSource("UTC")
        clock.date = date("2026-10-22T16:00:00Z")
        let manager = repository(calendarSource: source)
        let start = clock.date
        source.change(to: "Asia/Shanghai")
        clock.date = start.addingTimeInterval(1)
        manager.recordWork(from: start, to: clock.date)
        let nextStart = clock.date
        clock.date = nextStart.addingTimeInterval(1)
        manager.recordWork(from: nextStart, to: clock.date)

        XCTAssertEqual(manager.getAllStatistics(), [
            DailyStatistics(date: "2026-10-22", workDuration: 1),
            DailyStatistics(date: "2026-10-23", workDuration: 1)
        ])
    }

    func testSeveralTimeZoneChangesWithinOnePendingIntervalDoNotDuplicateTime() {
        let source = CalendarSource("UTC")
        clock.date = date("2026-10-22T16:00:00Z")
        let manager = repository(calendarSource: source)
        let start = clock.date
        clock.date = start.addingTimeInterval(1)
        source.change(to: "Asia/Shanghai")
        manager.refreshToday()
        clock.date = start.addingTimeInterval(2)
        source.change(to: "America/Los_Angeles")
        manager.refreshToday()
        clock.date = start.addingTimeInterval(3)
        manager.recordWork(from: start, to: clock.date)

        XCTAssertEqual(manager.getAllStatistics(), [
            DailyStatistics(date: "2026-10-22", workDuration: 2),
            DailyStatistics(date: "2026-10-23", workDuration: 1)
        ])
    }

    func testFractionalSecondsRemainWithTheirOriginalDateAcrossSwitchAndReload() {
        let source = CalendarSource("UTC")
        clock.date = date("2026-10-22T16:00:00Z")
        let manager = repository(calendarSource: source)
        var start = clock.date
        clock.date = start.addingTimeInterval(0.5)
        manager.recordWork(from: start, to: clock.date)
        source.change(to: "Asia/Shanghai")
        manager.refreshToday()
        start = clock.date
        clock.date = start.addingTimeInterval(0.5)
        manager.recordWork(from: start, to: clock.date)
        manager.flush()

        let reloaded = repository(calendarSource: source)
        start = clock.date
        clock.date = start.addingTimeInterval(0.5)
        reloaded.recordWork(from: start, to: clock.date)
        source.change(to: "UTC")
        reloaded.refreshToday()
        start = clock.date
        clock.date = start.addingTimeInterval(0.5)
        reloaded.recordWork(from: start, to: clock.date)
        XCTAssertEqual(reloaded.getAllStatistics(), [
            DailyStatistics(date: "2026-10-22", workDuration: 1),
            DailyStatistics(date: "2026-10-23", workDuration: 1)
        ])
    }

    func testTimeZoneChangeKeepsCompletionIDsOnTheirOriginalDates() {
        let source = CalendarSource("Asia/Shanghai")
        clock.date = date("2026-10-22T16:00:00Z")
        let manager = repository(calendarSource: source)
        let completedAt = clock.date
        let firstID = UUID()
        manager.recordCompletedRest(at: completedAt, id: firstID)
        source.change(to: "America/Los_Angeles")
        manager.refreshToday()
        manager.recordCompletedRest(at: completedAt, id: firstID)
        clock.date = completedAt.addingTimeInterval(1)
        manager.recordCompletedRest(at: clock.date, id: UUID())
        let reloaded = repository(calendarSource: source)
        source.change(to: "Asia/Shanghai")
        reloaded.refreshToday()
        reloaded.recordCompletedRest(at: completedAt, id: firstID)

        XCTAssertEqual(reloaded.getAllStatistics(), [
            DailyStatistics(date: "2026-10-22", restCount: 1),
            DailyStatistics(date: "2026-10-23", restCount: 1)
        ])
    }

    func testRetentionFollowsCurrentLocalDatesWhileFutureRecordsRemainStored() throws {
        let source = CalendarSource("UTC")
        clock.date = date("2026-10-22T16:00:00Z")
        defaults.set(try JSONEncoder().encode([
            DailyStatistics(date: "2026-10-20", restCount: 1),
            DailyStatistics(date: "2026-10-21", restCount: 1),
            DailyStatistics(date: "2026-10-22", restCount: 1),
            DailyStatistics(date: "2026-10-23", restCount: 1),
            DailyStatistics(date: "2026-10-24", restCount: 1)
        ]), forKey: "dailyStatisticsData")
        let manager = repository(calendarSource: source, retentionDays: 2)
        XCTAssertEqual(manager.getAllStatistics().map(\.date), ["2026-10-21", "2026-10-22", "2026-10-23", "2026-10-24"])
        source.change(to: "Asia/Shanghai")
        manager.flush()
        XCTAssertEqual(manager.getAllStatistics().map(\.date), ["2026-10-22", "2026-10-23", "2026-10-24"])
        source.change(to: "America/Los_Angeles")
        manager.refreshToday()
        XCTAssertEqual(manager.getWeeklyStatistics().map(\.date), ["2026-10-22"])
        XCTAssertEqual(repository(calendarSource: source, retentionDays: 2).getAllStatistics().map(\.date),
                       ["2026-10-22", "2026-10-23", "2026-10-24"])
    }

    func testSnapshotRefreshesAndNotifiesEvenWhenTimeZoneChangeKeepsTheSameDate() {
        let source = CalendarSource("UTC")
        let manager = repository(calendarSource: source)
        let originalData = defaults.data(forKey: "statisticsStoreV2")
        var changes = 0
        let token = NotificationCenter.default.addObserver(forName: StatisticsManager.didChangeNotification,
                                                           object: nil, queue: nil) { notification in
            if let sender = notification.object as? StatisticsManager, sender === manager { changes += 1 }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        source.change(to: "Europe/Paris")
        let snapshot = manager.getSnapshot()

        XCTAssertEqual(changes, 1)
        XCTAssertEqual(snapshot.calendar.timeZone.identifier, "Europe/Paris")
        XCTAssertEqual(snapshot.referenceDate, clock.date)
        XCTAssertTrue(snapshot.records.isEmpty)
        XCTAssertEqual(manager.refreshToday().date, "2026-10-22")
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(defaults.data(forKey: "statisticsStoreV2"), originalData)
    }

    func testClockRollbackAfterTimeZoneChangeUsesTheCurrentZoneAndKeepsFutureHistory() {
        let source = CalendarSource("UTC")
        let manager = repository(calendarSource: source)
        source.change(to: "America/Los_Angeles")
        manager.refreshToday()
        clock.date = date("2026-10-22T13:00:00Z")
        manager.recordWork(from: clock.date.addingTimeInterval(-1), to: clock.date)
        clock.date = date("2026-10-22T04:00:00Z")
        manager.recordWork(from: clock.date.addingTimeInterval(-1), to: clock.date)

        XCTAssertEqual(manager.getTodayStatistics(), DailyStatistics(date: "2026-10-21", workDuration: 1))
        XCTAssertEqual(manager.getAllStatistics(), [
            DailyStatistics(date: "2026-10-21", workDuration: 1),
            DailyStatistics(date: "2026-10-22", workDuration: 1)
        ])
    }

    func testChangingCalendarIdentifierDoesNotReinterpretOrDeleteExistingDateKeys() {
        let source = CalendarSource("UTC")
        clock.date = date("2026-10-22T16:00:00Z")
        let manager = repository(calendarSource: source)
        manager.recordCompletedRest(at: clock.date, id: UUID())
        source.calendar = Calendar(identifier: .buddhist)
        source.calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        manager.refreshToday()
        let start = clock.date
        clock.date = start.addingTimeInterval(1)
        manager.recordWork(from: start, to: clock.date)

        XCTAssertEqual(manager.getSnapshot().calendar.identifier, .gregorian)
        XCTAssertEqual(manager.getTodayStatistics().date, "2026-10-23")
        XCTAssertEqual(manager.getAllStatistics(), [
            DailyStatistics(date: "2026-10-22", restCount: 1),
            DailyStatistics(date: "2026-10-23", workDuration: 1)
        ])
    }

    func testProcessedWorkDiscardsOldCalendarContextsDuringRepeatedTimeZoneChanges() {
        let source = CalendarSource("UTC")
        clock.date = date("2026-10-22T16:00:00Z")
        let manager = repository(calendarSource: source)
        for index in 0..<128 {
            let start = clock.date
            clock.date = start.addingTimeInterval(1)
            source.change(to: index.isMultiple(of: 2) ? "Asia/Shanghai" : "America/Los_Angeles")
            manager.refreshToday()
            clock.date = start.addingTimeInterval(2)
            manager.recordWork(from: start, to: clock.date)
            XCTAssertEqual(manager.retainedCalendarContextCount, 1)
        }
        XCTAssertEqual(manager.getAllStatistics().reduce(0) { $0 + $1.workDuration }, 256)
    }

    func testOldCalendarContextsExpireEvenWithoutWorkSubmissions() {
        let source = CalendarSource("UTC")
        let manager = repository(calendarSource: source)
        for index in 0..<130 {
            clock.date = clock.date.addingTimeInterval(86400)
            source.change(to: index.isMultiple(of: 2) ? "Asia/Shanghai" : "UTC")
            manager.refreshToday()
        }
        XCTAssertLessThanOrEqual(manager.retainedCalendarContextCount, 91)
        XCTAssertTrue(manager.getAllStatistics().isEmpty)
    }

    func testReloadAfterSystemCalendarChangePreservesGregorianHistoryAndCompletionIDs() {
        let source = CalendarSource("UTC")
        clock.date = date("2026-10-22T16:00:00Z")
        let original = repository(calendarSource: source)
        let completedAt = clock.date
        let completedID = UUID()
        original.recordCompletedRest(at: completedAt, id: completedID)
        let savedData = defaults.data(forKey: "statisticsStoreV2")

        source.calendar = Calendar(identifier: .buddhist)
        source.calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let reloaded = repository(calendarSource: source)
        XCTAssertEqual(defaults.data(forKey: "statisticsStoreV2"), savedData)
        XCTAssertEqual(reloaded.getSnapshot().calendar.identifier, .gregorian)
        XCTAssertEqual(reloaded.getTodayStatistics(), DailyStatistics(date: "2026-10-23"))
        reloaded.recordCompletedRest(at: completedAt, id: completedID)
        clock.date = completedAt.addingTimeInterval(1)
        reloaded.recordWork(from: completedAt, to: clock.date)
        reloaded.flush()

        let expected = [DailyStatistics(date: "2026-10-22", restCount: 1),
                        DailyStatistics(date: "2026-10-23", workDuration: 1)]
        let nextLaunch = repository(calendarSource: source)
        XCTAssertEqual(nextLaunch.getAllStatistics(), expected)
        let presentation = StatisticsPresentation(snapshot: nextLaunch.getSnapshot())
        XCTAssertEqual(presentation.calendar.identifier, .gregorian)
        XCTAssertEqual(presentation.days.last?.id, "2026-10-23")
        XCTAssertEqual(presentation.exportRecords, expected)
        XCTAssertEqual(presentation.csvFilename, "lumenfocus-stats-2026-10-17-2026-10-23.csv")
    }

    func testExplicitCalendarInjectsAFixedTimeZoneWithoutChangingGregorianDateKeys() {
        clock.date = date("2026-10-22T16:00:00Z")
        var suppliedCalendar = Calendar(identifier: .buddhist)
        suppliedCalendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let testClock = clock!
        let manager = StatisticsManager(defaults: defaults, calendar: suppliedCalendar, now: { testClock.date })
        suppliedCalendar.timeZone = TimeZone(identifier: "UTC")!

        XCTAssertEqual(manager.getSnapshot().calendar.identifier, .gregorian)
        XCTAssertEqual(manager.getSnapshot().calendar.timeZone.identifier, "Asia/Shanghai")
        XCTAssertEqual(manager.getTodayStatistics().date, "2026-10-23")
        manager.recordCompletedRest(at: clock.date, id: UUID())
        XCTAssertEqual(manager.getAllStatistics(), [DailyStatistics(date: "2026-10-23", restCount: 1)])
    }
}
