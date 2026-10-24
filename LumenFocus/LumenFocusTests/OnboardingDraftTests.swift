import XCTest
@testable import LumenFocus

final class OnboardingDraftTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "LumenFocus.OnboardingDraftTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testStartSavesTheVisibleDraftRatherThanExistingDefaults() {
        let settings = AppSettings(defaults: defaults)
        var draft = OnboardingDraft(settings: settings, launchAtLogin: false)
        draft.workMinutes = 20
        draft.restSeconds = 20
        draft.launchAtLogin = true
        settings.remindersEnabled = false
        settings.remindersPausedUntil = Date().addingTimeInterval(3600)
        var actualLoginState = false
        XCTAssertTrue(draft.commit(to: settings, readLaunchAtLogin: { actualLoginState },
                                   setLaunchAtLogin: { actualLoginState = $0; return true }))
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.workDurationMinutes, 20)
        XCTAssertEqual(reloaded.restDurationSeconds, 20)
        XCTAssertTrue(reloaded.remindersEnabled)
        XCTAssertNil(reloaded.remindersPausedUntil)
        XCTAssertTrue(reloaded.launchAtLogin)
        XCTAssertTrue(reloaded.hasCompletedOnboarding)
    }

    func testDiscardingAnEditedDraftDoesNotSaveOrCompleteSetup() {
        let settings = AppSettings(defaults: defaults)
        let pauseUntil = Date(timeIntervalSince1970: 1_800_000_000)
        settings.remindersEnabled = true
        settings.remindersPausedUntil = pauseUntil
        do {
            var draft = OnboardingDraft(settings: settings, launchAtLogin: false)
            draft.workMinutes = 20
            draft.restSeconds = 20
            draft.launchAtLogin = true
            XCTAssertEqual(draft.restSeconds, 20)
        }
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.workDurationMinutes, 40)
        XCTAssertEqual(reloaded.restDurationSeconds, 300)
        XCTAssertFalse(reloaded.launchAtLogin)
        XCTAssertFalse(reloaded.hasCompletedOnboarding)
        XCTAssertTrue(reloaded.remindersEnabled)
        XCTAssertEqual(reloaded.remindersPausedUntil, pauseUntil)
    }

    func testDiscardingSetupKeepsStoppedRemindersStopped() {
        let settings = AppSettings(defaults: defaults)
        settings.remindersEnabled = false
        var draft = OnboardingDraft(settings: settings, launchAtLogin: false)
        draft.workMinutes = 60
        XCTAssertEqual(draft.workMinutes, 60)
        XCTAssertFalse(AppSettings(defaults: defaults).remindersEnabled)
        XCTAssertFalse(settings.hasCompletedOnboarding)
    }

    func testFailedLoginChangeDoesNotPartiallySaveAndCanRetryWithActualState() {
        let settings = AppSettings(defaults: defaults)
        var draft = OnboardingDraft(settings: settings, launchAtLogin: false)
        draft.workMinutes = 20
        draft.restSeconds = 20
        draft.launchAtLogin = true
        settings.remindersEnabled = false
        XCTAssertFalse(draft.commit(to: settings, readLaunchAtLogin: { false }, setLaunchAtLogin: { _ in false }))
        XCTAssertEqual(settings.workDurationMinutes, 40)
        XCTAssertEqual(settings.restDurationSeconds, 300)
        XCTAssertFalse(settings.hasCompletedOnboarding)
        XCTAssertFalse(settings.remindersEnabled)

        draft.launchAtLogin = false
        XCTAssertTrue(draft.commit(to: settings, readLaunchAtLogin: { false }, setLaunchAtLogin: { _ in
            XCTFail("Retrying with the actual state must not change the system setting")
            return false
        }))
        XCTAssertEqual(AppSettings(defaults: defaults).restDurationSeconds, 20)
        XCTAssertTrue(settings.hasCompletedOnboarding)
    }

    func testReportedLoginSuccessMustMatchTheActualSystemState() {
        let settings = AppSettings(defaults: defaults)
        var draft = OnboardingDraft(settings: settings, launchAtLogin: false)
        draft.launchAtLogin = true
        XCTAssertFalse(draft.commit(to: settings, readLaunchAtLogin: { false }, setLaunchAtLogin: { _ in true }))
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertFalse(settings.hasCompletedOnboarding)
    }
}
