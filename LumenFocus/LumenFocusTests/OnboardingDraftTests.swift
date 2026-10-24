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
        draft.reminderMode = .immersive
        draft.launchAtLogin = true
        var actualLoginState = false
        XCTAssertTrue(draft.commit(to: settings, readLaunchAtLogin: { actualLoginState },
                                   setLaunchAtLogin: { actualLoginState = $0; return true }))
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.workDurationMinutes, 20)
        XCTAssertEqual(reloaded.restDurationSeconds, 20)
        XCTAssertEqual(reloaded.reminderMode, .immersive)
        XCTAssertTrue(reloaded.launchAtLogin)
        XCTAssertTrue(reloaded.hasCompletedOnboarding)
    }

    func testDiscardingAnEditedDraftDoesNotSaveOrCompleteSetup() {
        let settings = AppSettings(defaults: defaults)
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
    }

    func testFailedLoginChangeDoesNotPartiallySaveAndCanRetryWithActualState() {
        let settings = AppSettings(defaults: defaults)
        var draft = OnboardingDraft(settings: settings, launchAtLogin: false)
        draft.workMinutes = 20
        draft.restSeconds = 20
        draft.launchAtLogin = true
        XCTAssertFalse(draft.commit(to: settings, readLaunchAtLogin: { false }, setLaunchAtLogin: { _ in false }))
        XCTAssertEqual(settings.workDurationMinutes, 40)
        XCTAssertEqual(settings.restDurationSeconds, 300)
        XCTAssertFalse(settings.hasCompletedOnboarding)

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
