// Preferences are persisted independently from runtime state. Environment consumers
// observe these values; changing a preference never initializes another singleton.
import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case en
    case ja
    case fr
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: return L("跟随系统")
        case .zhHans: return "简体中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .fr: return "Français"
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults: UserDefaults

    @Published var workDurationMinutes: Int {
        didSet { defaults.set(workDurationMinutes, forKey: Keys.workDuration) }
    }
    /// The actual time away from the screen, excluding fade-in and fade-out.
    @Published var restDurationSeconds: Int {
        didSet { defaults.set(restDurationSeconds, forKey: Keys.restDurationSeconds) }
    }
    @Published var remindersEnabled: Bool {
        didSet { defaults.set(remindersEnabled, forKey: Keys.remindersEnabled) }
    }
    @Published var remindersPausedUntil: Date? {
        didSet {
            if let date = remindersPausedUntil { defaults.set(date, forKey: Keys.remindersPausedUntil) }
            else { defaults.removeObject(forKey: Keys.remindersPausedUntil) }
        }
    }
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }
    @Published var showRemainingMinutesInMenuBar: Bool {
        didSet { defaults.set(showRemainingMinutesInMenuBar, forKey: Keys.showRemainingMinutesInMenuBar) }
    }
    @Published var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: Keys.appLanguage)
            Self.applyLanguagePreference(appLanguage, defaults: defaults)
        }
    }
    /// Capture the launch preference. Bundle/AppKit localization stays fixed until relaunch.
    let appliedLanguage: AppLanguage
    var hasPendingLanguageChange: Bool { appLanguage != appliedLanguage }

    private enum Keys {
        static let workDuration = "workDurationMinutes"
        static let legacyRestDuration = "restDurationMinutes"
        static let restDurationSeconds = "restDurationSeconds"
        static let remindersEnabled = "remindersEnabled"
        static let remindersPausedUntil = "remindersPausedUntil"
        static let launchAtLogin = "launchAtLogin"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let showRemainingMinutesInMenuBar = "showRemainingMinutesInMenuBar"
        static let appLanguage = "appLanguage"
    }

    static let defaultWorkDuration = 40
    static let defaultRestDurationSeconds = 300
    static let workDurationRange = 15...120
    static let restDurationSecondsRange = 20...900
    static let privacyPolicyURLString = "https://yvettel19.github.io/LumenFocus/"
    static let supportEmail = "yveluo@outlook.com"

    /// An explicit defaults suite makes tests independent of the user's preferences.
    init(defaults: UserDefaults = .standard, now: Date = Date()) {
        self.defaults = defaults
        let work = defaults.object(forKey: Keys.workDuration) as? Int ?? Self.defaultWorkDuration
        workDurationMinutes = min(Self.workDurationRange.upperBound, max(Self.workDurationRange.lowerBound, work))
        let rest: Int
        if let seconds = defaults.object(forKey: Keys.restDurationSeconds) as? Int {
            rest = seconds
        } else if let minutes = defaults.object(forKey: Keys.legacyRestDuration) as? Int {
            // Clamp before multiplying so malformed legacy values cannot overflow.
            rest = min(15, max(1, minutes)) * 60
        } else {
            rest = Self.defaultRestDurationSeconds
        }
        let boundedRest = min(Self.restDurationSecondsRange.upperBound, max(Self.restDurationSecondsRange.lowerBound, rest))
        restDurationSeconds = boundedRest
        defaults.set(boundedRest, forKey: Keys.restDurationSeconds)
        let enabled = defaults.object(forKey: Keys.remindersEnabled) as? Bool ?? true
        remindersEnabled = enabled
        let savedPause = defaults.object(forKey: Keys.remindersPausedUntil) as? Date
        if enabled, let savedPause, savedPause.timeIntervalSinceReferenceDate.isFinite, savedPause > now {
            remindersPausedUntil = savedPause
        } else {
            remindersPausedUntil = nil
            defaults.removeObject(forKey: Keys.remindersPausedUntil)
        }
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        showRemainingMinutesInMenuBar = defaults.bool(forKey: Keys.showRemainingMinutesInMenuBar)
        let language = AppLanguage(rawValue: defaults.string(forKey: Keys.appLanguage) ?? "") ?? .system
        appLanguage = language
        appliedLanguage = language
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }

    static func applyLanguagePreference(_ language: AppLanguage, defaults: UserDefaults = .standard) {
        switch language {
        case .system: defaults.removeObject(forKey: "AppleLanguages")
        case .zhHans, .en, .ja, .fr: defaults.set([language.rawValue], forKey: "AppleLanguages")
        }
    }

    func resetToDefaults() {
        workDurationMinutes = Self.defaultWorkDuration
        restDurationSeconds = Self.defaultRestDurationSeconds
        // Reset preferences without reversing the user's current stop/pause decision.
        launchAtLogin = false
        showRemainingMinutesInMenuBar = false
        appLanguage = .system
    }

    func validateSettings() -> Bool {
        Self.workDurationRange.contains(workDurationMinutes) && Self.restDurationSecondsRange.contains(restDurationSeconds)
    }
}
