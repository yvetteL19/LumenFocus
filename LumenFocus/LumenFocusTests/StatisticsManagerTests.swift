//
//  StatisticsManagerTests.swift
//  LumenFocusTests
//

import XCTest
@testable import LumenFocus

final class StatisticsManagerTests: XCTestCase {
    private let testSuiteName = "Yvette.LumenFocus.tests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: testSuiteName)
        defaults.removePersistentDomain(forName: testSuiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: testSuiteName)
        super.tearDown()
    }

    func test_dailyStatisticsCodable_roundtrip() throws {
        let stats = DailyStatistics(date: "2026-06-02", restCount: 7, workDuration: 40 * 60)
        let data = try JSONEncoder().encode(stats)
        let decoded = try JSONDecoder().decode(DailyStatistics.self, from: data)
        XCTAssertEqual(decoded.date, "2026-06-02")
        XCTAssertEqual(decoded.restCount, 7)
        XCTAssertEqual(decoded.workDuration, 40 * 60)
    }

    func test_weeklyStatistics_returnsSevenDays() {
        let weekly = StatisticsManager.shared.getWeeklyStatistics()
        XCTAssertEqual(weekly.count, 7, "Weekly view always returns exactly 7 daily entries")
    }

    func test_weeklyWorkDurationFormatted_isNonEmpty() {
        let formatted = StatisticsManager.shared.getWeeklyWorkDurationFormatted()
        XCTAssertFalse(formatted.isEmpty)
    }
}
