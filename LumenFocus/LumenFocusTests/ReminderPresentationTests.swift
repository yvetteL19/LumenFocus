import XCTest
@testable import LumenFocus

final class ReminderPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let english: [String: String] = [
        "还有 %@": "In %@",
        "%d 秒": "%d sec",
        "%d 分钟": "%d min",
        "%d 分 %d 秒": "%d min %d sec",
        "即将提醒": "Reminder coming up",
        "工作 %@ · 休息 %@": "Work %@ · break %@",
        "暂停 %d 分钟 · %@": "Pause %d min · until %@"
    ]

    private func presentation(_ phase: AppPhase, seconds: Int = 0, due: Date? = nil,
                              detail: String? = nil) -> ReminderPresentation {
        ReminderPresentation(phase: phase, remainingSeconds: seconds,
                             nextReminderDate: due, environmentDetail: detail)
    }

    func testSubMinuteRemainingTimeShowsSecondsInBothLanguages() {
        XCTAssertEqual(ReminderPresentation.remainingDescription(seconds: 59, localize: { $0 }), "还有 59 秒")
        XCTAssertEqual(ReminderPresentation.remainingDescription(seconds: 59, localize: { english[$0] ?? $0 }), "In 59 sec")
        XCTAssertEqual(ReminderPresentation.remainingDescription(seconds: 1, localize: { english[$0] ?? $0 }), "In 1 sec")
        XCTAssertEqual(ReminderPresentation.remainingDescription(seconds: 0, localize: { $0 }), "即将提醒")
        XCTAssertEqual(ReminderPresentation.remainingDescription(seconds: -1, localize: { $0 }), "即将提醒")
    }

    func testMinuteBoundaryDoesNotDiscardRemainingSeconds() {
        XCTAssertEqual(ReminderPresentation.remainingDescription(seconds: 60, localize: { $0 }), "还有 1 分钟")
        XCTAssertEqual(ReminderPresentation.remainingDescription(seconds: 61, localize: { $0 }), "还有 1 分 1 秒")
        XCTAssertEqual(ReminderPresentation.remainingDescription(seconds: 119, localize: { english[$0] ?? $0 }), "In 1 min 59 sec")
    }

    func testMenuBarCompactCountdownDistinguishesSubMinuteAndDueStates() {
        XCTAssertEqual(ReminderPresentation.menuBarCountdown(seconds: -1), "0m")
        XCTAssertEqual(ReminderPresentation.menuBarCountdown(seconds: 0), "0m")
        XCTAssertEqual(ReminderPresentation.menuBarCountdown(seconds: 1), "<1m")
        XCTAssertEqual(ReminderPresentation.menuBarCountdown(seconds: 59), "<1m")
        XCTAssertEqual(ReminderPresentation.menuBarCountdown(seconds: 60), "1m")
        XCTAssertEqual(ReminderPresentation.menuBarCountdown(seconds: 61), "2m")
    }

    func testPrimaryActionsMatchTheMeaningOfEveryState() {
        XCTAssertEqual(presentation(.working).primaryAction, .startRest)
        XCTAssertEqual(presentation(.reminderDue).primaryAction, .startRest)
        XCTAssertEqual(presentation(.triggeringRest).primaryAction, .endRest)
        XCTAssertEqual(presentation(.resting).primaryAction, .endRest)
        XCTAssertEqual(presentation(.autoSuspended(reason: .videoCall)).primaryAction, .startRest)
        let paused = presentation(.paused(until: .duration(now.addingTimeInterval(900))))
        XCTAssertEqual(paused.primaryAction, .resumeReminders)
        XCTAssertEqual(paused.primaryTitleKey, "恢复提醒")
        XCTAssertEqual(paused.pauseMenuTitleKey, "调整暂停时间")
    }

    func testDisplayedDelayUsesUpcomingDeadlineButDueAndRestUseNow() {
        let due = now.addingTimeInterval(600)
        XCTAssertEqual(presentation(.working, due: due).delayedReminderDate(minutes: 5, now: now), due.addingTimeInterval(300))
        XCTAssertEqual(presentation(.reminderDue, due: due).delayedReminderDate(minutes: 5, now: now), now.addingTimeInterval(300))
        XCTAssertEqual(presentation(.resting).delayedReminderDate(minutes: 2, now: now), now.addingTimeInterval(120))
        XCTAssertEqual(presentation(.working, due: now.addingTimeInterval(-10)).delayedReminderDate(minutes: 5, now: now), now.addingTimeInterval(300))
    }

    func testRhythmSummaryPreservesTwentySecondAndMixedDurationBreaks() {
        XCTAssertEqual(ReminderPresentation.rhythmSummary(workMinutes: 40, restSeconds: 20, localize: { $0 }),
                       "工作 40 分钟 · 休息 20 秒")
        XCTAssertEqual(ReminderPresentation.rhythmSummary(workMinutes: 20, restSeconds: 90, localize: { english[$0] ?? $0 }),
                       "Work 20 min · break 1 min 30 sec")
    }

    func testPauseOptionsIncludeBothDurationAndExactEndTime() {
        var renderedDate: Date?
        let title = ReminderPresentation.pauseOptionTitle(minutes: 15, now: now,
                                                         localize: { english[$0] ?? $0 },
                                                         clockText: { renderedDate = $0; return "14:15" })
        XCTAssertEqual(title, "Pause 15 min · until 14:15")
        XCTAssertEqual(renderedDate, now.addingTimeInterval(900))
    }

    func testWorkingEnvironmentExplanationDoesNotHideCountdown() {
        let state = presentation(.working, seconds: 45, detail: "Light reminders while idle.")
        XCTAssertEqual(state.detail(localize: { english[$0] ?? $0 }), "In 45 sec\nLight reminders while idle.")
    }

    func testPausedAndRestingValuesDoNotShowAWorkingReminderTime() {
        let paused = presentation(.paused(until: .duration(now)), seconds: 123, due: now)
        XCTAssertEqual(paused.value(localize: { $0 }, clockText: { _ in "14:00" }), "14:00")
        XCTAssertEqual(presentation(.paused(until: .endOfDay)).value(localize: { $0 }), "至今日结束")
        XCTAssertEqual(presentation(.resting, seconds: 20, due: now).value(localize: { $0 }), "0:20")
        XCTAssertEqual(presentation(.resting, seconds: -1).value(localize: { $0 }), "0:00")
    }
}
