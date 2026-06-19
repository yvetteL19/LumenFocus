//
//  AppSettingsTests.swift
//  LumenFocusTests
//

import XCTest
@testable import LumenFocus

final class AppSettingsTests: XCTestCase {
    func test_defaultValues_areWithinRange() {
        XCTAssertTrue(AppSettings.workDurationRange.contains(AppSettings.defaultWorkDuration))
        XCTAssertTrue(AppSettings.restDurationRange.contains(AppSettings.defaultRestDuration))
    }

    func test_validateSettings_acceptsDefaults() {
        let settings = AppSettings.shared
        let originalWork = settings.workDurationMinutes
        let originalRest = settings.restDurationMinutes
        defer {
            settings.workDurationMinutes = originalWork
            settings.restDurationMinutes = originalRest
        }

        settings.workDurationMinutes = AppSettings.defaultWorkDuration
        settings.restDurationMinutes = AppSettings.defaultRestDuration
        XCTAssertTrue(settings.validateSettings())
    }

    func test_validateSettings_rejectsOutOfRange() {
        let settings = AppSettings.shared
        let originalWork = settings.workDurationMinutes
        let originalRest = settings.restDurationMinutes
        defer {
            settings.workDurationMinutes = originalWork
            settings.restDurationMinutes = originalRest
        }

        settings.workDurationMinutes = 1   // below 15
        settings.restDurationMinutes = AppSettings.defaultRestDuration
        XCTAssertFalse(settings.validateSettings())

        settings.workDurationMinutes = AppSettings.defaultWorkDuration
        settings.restDurationMinutes = 999  // above 15
        XCTAssertFalse(settings.validateSettings())
    }
}
