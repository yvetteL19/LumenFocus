import XCTest
@testable import LumenFocus

final class StatisticsManagerTests: XCTestCase {
    private final class Clock {
        var date: Date
        init(_ date: Date) { self.date = date }
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
}
