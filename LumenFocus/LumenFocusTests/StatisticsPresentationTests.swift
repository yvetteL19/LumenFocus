import XCTest
@testable import LumenFocus

final class StatisticsPresentationTests: XCTestCase {
    private func calendar(_ timeZone: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    func testRangesIncludeTodayAndExactlyTheRequestedCalendarDays() {
        let now = date("2026-01-03T22:30:00Z")
        let firstDates: [StatisticsRange: String] = [
            .sevenDays: "2025-12-28", .thirtyDays: "2025-12-05", .ninetyDays: "2025-10-06"
        ]
        for range in StatisticsRange.allCases {
            let result = StatisticsPresentation(records: [], range: range, now: now, calendar: calendar())
            XCTAssertEqual(result.days.count, range.rawValue)
            XCTAssertEqual(Set(result.days.map(\.id)).count, range.rawValue)
            XCTAssertEqual(result.days.first?.id, firstDates[range])
            XCTAssertEqual(result.days.last?.id, "2026-01-03")
            XCTAssertEqual(result.endDateExclusive, date("2026-01-04T00:00:00Z"))
        }
    }

    func testRangeUsesTheLocalDayWhenItDiffersFromUTC() {
        let now = date("2026-10-22T16:30:00Z")
        let result = StatisticsPresentation(records: [
            DailyStatistics(date: "2026-10-23", restCount: 1)
        ], now: now, calendar: calendar("Asia/Shanghai"))
        XCTAssertEqual(result.days.first?.id, "2026-10-17")
        XCTAssertEqual(result.days.last?.id, "2026-10-23")
        XCTAssertEqual(result.endDate, date("2026-10-22T16:00:00Z"))
        XCTAssertEqual(result.completedRestCount, 1)
    }

    func testSpringDaylightSavingKeepsCalendarDatesAcrossAShortDay() {
        let result = StatisticsPresentation(records: [], now: date("2026-03-10T12:00:00-07:00"),
                                            calendar: calendar("America/Los_Angeles"))
        XCTAssertEqual(result.days.map(\.id), ["2026-03-04", "2026-03-05", "2026-03-06", "2026-03-07",
                                              "2026-03-08", "2026-03-09", "2026-03-10"])
        let shortDay = result.days[5].date.timeIntervalSince(result.days[4].date)
        XCTAssertEqual(shortDay, 23 * 3600)
        XCTAssertEqual(result.endDateExclusive.timeIntervalSince(result.startDate), 7 * 86400 - 3600)
    }

    func testAutumnDaylightSavingKeepsCalendarDatesAcrossALongDay() {
        let result = StatisticsPresentation(records: [], now: date("2026-11-03T12:00:00-08:00"),
                                            calendar: calendar("America/Los_Angeles"))
        XCTAssertEqual(result.days.map(\.id), ["2026-10-28", "2026-10-29", "2026-10-30", "2026-10-31",
                                              "2026-11-01", "2026-11-02", "2026-11-03"])
        let longDay = result.days[5].date.timeIntervalSince(result.days[4].date)
        XCTAssertEqual(longDay, 25 * 3600)
        XCTAssertEqual(result.endDateExclusive.timeIntervalSince(result.startDate), 7 * 86400 + 3600)
    }

    func testLeapDayIsIncludedAndRecordsOutsideTheRangeAreExcluded() {
        let result = StatisticsPresentation(records: [
            DailyStatistics(date: "2024-02-23", restCount: 10),
            DailyStatistics(date: "2024-02-24", restCount: 1),
            DailyStatistics(date: "2024-02-29", restCount: 2),
            DailyStatistics(date: "2024-03-01", restCount: 3),
            DailyStatistics(date: "2024-03-02", restCount: 20),
            DailyStatistics(date: "2024-02-30", restCount: 30)
        ], now: date("2024-03-01T00:00:00Z"), calendar: calendar())
        XCTAssertEqual(result.days.count, 7)
        XCTAssertEqual(result.days.first?.id, "2024-02-24")
        XCTAssertEqual(result.days.last?.id, "2024-03-01")
        XCTAssertEqual(result.completedRestCount, 6)
        XCTAssertEqual(result.exportRecords.map(\.date), ["2024-02-24", "2024-02-29", "2024-03-01"])
    }

    func testMissingAndZeroRecordsRemainDistinctAndDoNotCountAsActiveDays() {
        let result = StatisticsPresentation(records: [
            DailyStatistics(date: "2026-10-21", restCount: 2),
            DailyStatistics(date: "2026-10-22", workDuration: 1),
            DailyStatistics(date: "2026-10-23")
        ], now: date("2026-10-23T12:00:00Z"), calendar: calendar())
        XCTAssertNil(result.days.first?.record)
        XCTAssertEqual(result.days.last?.record, DailyStatistics(date: "2026-10-23"))
        XCTAssertFalse(result.days.last!.hasActivity)
        XCTAssertEqual(result.activeDayCount, 2)
        XCTAssertEqual(result.timedWorkSeconds, 1)
        XCTAssertEqual(result.completedRestCount, 2)
        XCTAssertTrue(result.hasRecords)
        XCTAssertTrue(result.hasActivity)

        let zeroOnly = StatisticsPresentation(records: [DailyStatistics(date: "2026-10-23")],
                                              now: date("2026-10-23T12:00:00Z"), calendar: calendar())
        XCTAssertTrue(zeroOnly.hasRecords)
        XCTAssertFalse(zeroOnly.hasActivity)
        XCTAssertEqual(zeroOnly.activeDayCount, 0)
        let missing = StatisticsPresentation(records: [], now: date("2026-10-23T12:00:00Z"), calendar: calendar())
        XCTAssertFalse(missing.hasRecords)
        XCTAssertFalse(missing.hasActivity)
    }

    func testRangeChangesSummaryAndExportTogether() {
        let records = [
            DailyStatistics(date: "2026-10-23", restCount: 1, workDuration: 10),
            DailyStatistics(date: "2026-10-10", restCount: 2, workDuration: 20),
            DailyStatistics(date: "2026-08-01", restCount: 4, workDuration: 40),
            DailyStatistics(date: "2026-07-25", restCount: 8, workDuration: 80),
            DailyStatistics(date: "2026-10-24", restCount: 16, workDuration: 160)
        ]
        let expected = [(StatisticsRange.sevenDays, 1, 10, 1), (.thirtyDays, 3, 30, 2), (.ninetyDays, 7, 70, 3)]
        for (range, rests, work, activeDays) in expected {
            let result = StatisticsPresentation(records: records, range: range,
                                                now: date("2026-10-23T12:00:00Z"), calendar: calendar())
            XCTAssertEqual(result.completedRestCount, rests)
            XCTAssertEqual(result.timedWorkSeconds, work)
            XCTAssertEqual(result.activeDayCount, activeDays)
            XCTAssertEqual(result.exportRecords.count, activeDays)
        }
    }

    func testCSVContainsOnlySelectedStoredDatesAndPreservesActualZeroValues() {
        let result = StatisticsPresentation(records: [
            DailyStatistics(date: "2026-10-23"),
            DailyStatistics(date: "2026-10-17", restCount: 2, workDuration: 59),
            DailyStatistics(date: "2026-10-16", restCount: 5),
            DailyStatistics(date: "2026-10-24", restCount: 6)
        ], now: date("2026-10-23T12:00:00Z"), calendar: calendar())
        XCTAssertEqual(result.csvFilename, "lumenfocus-stats-2026-10-17-2026-10-23.csv")
        XCTAssertEqual(result.csvContents, "date,completed_rest_count,timed_work_seconds\n2026-10-17,2,59\n2026-10-23,0,0\n")
        XCTAssertEqual(result.exportRecords.count, 2)
        XCTAssertEqual(result.activeDayCount, 1)
    }

    func testChartLabelsIncludeBothBoundariesAndOnlyWholeRestCounts() {
        for range in StatisticsRange.allCases {
            let result = StatisticsPresentation(records: [DailyStatistics(date: "2026-10-23", restCount: 11)],
                                                range: range, now: date("2026-10-23T12:00:00Z"), calendar: calendar())
            XCTAssertEqual(result.chartTickDates.first, result.startDate)
            XCTAssertEqual(result.chartTickDates.last, result.endDate)
            XCTAssertLessThanOrEqual(result.chartTickDates.count, 7)
            XCTAssertEqual(result.chartTickCounts, [0, 3, 6, 9, 12])
        }
    }

    func testSnapshotKeepsAnAtomicCalendarRangeAcrossEastwardAndWestwardRefresh() {
        let instant = date("2026-10-22T16:30:00Z")
        let records = [DailyStatistics(date: "2026-10-22", workDuration: 20),
                       DailyStatistics(date: "2026-10-23", workDuration: 30)]
        let east = StatisticsPresentation(snapshot: .init(records: records, calendar: calendar("Asia/Shanghai"),
                                                          referenceDate: instant))
        let west = StatisticsPresentation(snapshot: .init(records: records, calendar: calendar("America/Los_Angeles"),
                                                          referenceDate: instant))

        XCTAssertEqual(east.days.last?.id, "2026-10-23")
        XCTAssertEqual(east.timedWorkSeconds, 50)
        XCTAssertEqual(east.calendar.timeZone.identifier, "Asia/Shanghai")
        XCTAssertEqual(west.days.last?.id, "2026-10-22")
        XCTAssertEqual(west.timedWorkSeconds, 20)
        XCTAssertEqual(west.calendar.timeZone.identifier, "America/Los_Angeles")
        XCTAssertEqual(west.exportRecords.map(\.date), ["2026-10-22"])
        // Creating the refreshed range cannot mutate an earlier snapshot.
        XCTAssertEqual(east.csvFilename, "lumenfocus-stats-2026-10-17-2026-10-23.csv")
    }

    func testSnapshotAfterMidnightMovesRangeWithoutInventingTodaysRecord() {
        let records = [DailyStatistics(date: "2026-10-22", restCount: 1)]
        let before = StatisticsPresentation(snapshot: .init(records: records, calendar: calendar("Asia/Shanghai"),
                                                            referenceDate: date("2026-10-22T15:59:59Z")))
        let after = StatisticsPresentation(snapshot: .init(records: records, calendar: calendar("Asia/Shanghai"),
                                                           referenceDate: date("2026-10-22T16:00:00Z")))
        XCTAssertEqual(before.days.last?.record?.restCount, 1)
        XCTAssertEqual(after.days.last?.id, "2026-10-23")
        XCTAssertNil(after.days.last?.record)
        XCTAssertEqual(after.exportRecords, records)
        XCTAssertEqual(after.activeDayCount, 1)
    }

    func testNonGregorianDisplayCalendarStillMatchesStoredDateKeysAndCSV() {
        var suppliedCalendar = Calendar(identifier: .buddhist)
        suppliedCalendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let records = [DailyStatistics(date: "2026-10-23", restCount: 1)]
        let result = StatisticsPresentation(records: records, now: date("2026-10-22T16:00:00Z"),
                                            calendar: suppliedCalendar)

        XCTAssertEqual(result.calendar.identifier, .gregorian)
        XCTAssertEqual(result.calendar.timeZone.identifier, "Asia/Shanghai")
        XCTAssertEqual(result.days.last?.id, "2026-10-23")
        XCTAssertEqual(result.days.last?.date, date("2026-10-22T16:00:00Z"))
        XCTAssertEqual(result.completedRestCount, 1)
        XCTAssertEqual(result.csvContents, "date,completed_rest_count,timed_work_seconds\n2026-10-23,1,0\n")
    }
}
