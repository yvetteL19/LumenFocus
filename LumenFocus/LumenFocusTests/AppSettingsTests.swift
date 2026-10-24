import XCTest
@testable import LumenFocus

final class AppSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "LumenFocus.SettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testNewInstallUsesGentleRemindersAndValidDefaults() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.reminderMode, .gentle)
        XCTAssertEqual(settings.workDurationMinutes, 40)
        XCTAssertEqual(settings.restDurationSeconds, 300)
        XCTAssertTrue(settings.validateSettings())
    }

    func testLegacyMinutesMigrateOnceWithoutOverwritingSeconds() {
        defaults.set(5, forKey: "restDurationMinutes")
        let migrated = AppSettings(defaults: defaults)
        XCTAssertEqual(migrated.restDurationSeconds, 300)
        migrated.restDurationSeconds = 20
        XCTAssertEqual(AppSettings(defaults: defaults).restDurationSeconds, 20)
    }

    func testTwentySecondRestPersistsExactly() {
        let settings = AppSettings(defaults: defaults)
        settings.restDurationSeconds = 20
        XCTAssertTrue(settings.validateSettings())
        XCTAssertEqual(AppSettings(defaults: defaults).restDurationSeconds, 20)
    }

    func testNewInstallFollowsSystemAndLanguageChangesWaitForRelaunch() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.appLanguage, .system)
        XCTAssertEqual(settings.appliedLanguage, .system)
        XCTAssertFalse(settings.hasPendingLanguageChange)
        settings.appLanguage = .fr
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["fr"])
        XCTAssertEqual(settings.appliedLanguage, .system)
        XCTAssertTrue(settings.hasPendingLanguageChange)
        settings.appLanguage = .system
        XCTAssertFalse(settings.hasPendingLanguageChange)
        XCTAssertNil(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"])
    }

    func testEveryExplicitLanguagePersistsAndBecomesAppliedAfterRelaunch() {
        for language in AppLanguage.allCases where language != .system {
            let settings = AppSettings(defaults: defaults)
            settings.appLanguage = language
            XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), [language.rawValue])
            let relaunched = AppSettings(defaults: defaults)
            XCTAssertEqual(relaunched.appLanguage, language)
            XCTAssertEqual(relaunched.appliedLanguage, language)
            XCTAssertFalse(relaunched.hasPendingLanguageChange)
        }
        XCTAssertEqual(Set(AppLanguage.allCases.filter { $0 != .system }.map(\.rawValue)),
                       Set(AppLocalization.supportedLanguages))
    }

    func testCorruptPersistedDurationsAreBounded() {
        defaults.set(Int.max, forKey: "restDurationMinutes")
        defaults.set(-100, forKey: "workDurationMinutes")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.restDurationSeconds, 900)
        XCTAssertEqual(settings.workDurationMinutes, 15)
        defaults.set(-1, forKey: "restDurationSeconds")
        XCTAssertEqual(AppSettings(defaults: defaults).restDurationSeconds, 20)
    }

    func testAllDetectionChoicesSurviveReload() {
        let settings = AppSettings(defaults: defaults)
        settings.enableSmartDetection = false
        settings.detectIdle = false
        settings.detectVideoCall = false
        settings.detectFullscreen = false
        settings.detectScreenLock = false
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertFalse(reloaded.enableSmartDetection)
        XCTAssertFalse(reloaded.detectIdle)
        XCTAssertFalse(reloaded.detectVideoCall)
        XCTAssertFalse(reloaded.detectFullscreen)
        XCTAssertFalse(reloaded.detectScreenLock)
    }

    func testResetRestoresEveryExposedPreferenceWithoutErasingOnboarding() {
        let settings = AppSettings(defaults: defaults)
        settings.hasCompletedOnboarding = true
        settings.workDurationMinutes = 90
        settings.restDurationSeconds = 20
        settings.reminderMode = .immersive
        settings.launchAtLogin = true
        settings.enableSmartDetection = false
        settings.detectIdle = false
        settings.detectVideoCall = false
        settings.detectFullscreen = false
        settings.detectScreenLock = false
        settings.ambientTrack = .rain
        settings.showRemainingMinutesInMenuBar = true
        settings.appLanguage = .en
        settings.resetToDefaults()
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.workDurationMinutes, 40)
        XCTAssertEqual(reloaded.restDurationSeconds, 300)
        XCTAssertEqual(reloaded.reminderMode, .gentle)
        XCTAssertFalse(reloaded.launchAtLogin)
        XCTAssertTrue(reloaded.enableSmartDetection)
        XCTAssertTrue(reloaded.detectIdle)
        XCTAssertTrue(reloaded.detectVideoCall)
        XCTAssertTrue(reloaded.detectFullscreen)
        XCTAssertTrue(reloaded.detectScreenLock)
        XCTAssertEqual(reloaded.ambientTrack, .off)
        XCTAssertFalse(reloaded.showRemainingMinutesInMenuBar)
        XCTAssertEqual(reloaded.appLanguage, .system)
        // System language remains inherited; only this app's override is removed.
        XCTAssertNil(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"])
        XCTAssertTrue(reloaded.hasCompletedOnboarding)
    }
}
