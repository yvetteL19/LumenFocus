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

enum ReminderMode: String, CaseIterable, Identifiable {
    case gentle
    case immersive
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .gentle: return L("提醒后手动开始")
        case .immersive: return L("到点自动渐暗")
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
    @Published var reminderMode: ReminderMode {
        didSet { defaults.set(reminderMode.rawValue, forKey: Keys.reminderMode) }
    }
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }
    @Published var enableSmartDetection: Bool {
        didSet { defaults.set(enableSmartDetection, forKey: Keys.enableSmartDetection) }
    }
    @Published var detectIdle: Bool {
        didSet { defaults.set(detectIdle, forKey: Keys.detectIdle) }
    }
    @Published var detectVideoCall: Bool {
        didSet { defaults.set(detectVideoCall, forKey: Keys.detectVideoCall) }
    }
    @Published var detectFullscreen: Bool {
        didSet { defaults.set(detectFullscreen, forKey: Keys.detectFullscreen) }
    }
    @Published var detectScreenLock: Bool {
        didSet { defaults.set(detectScreenLock, forKey: Keys.detectScreenLock) }
    }
    @Published var ambientTrack: AmbientTrack {
        didSet { defaults.set(ambientTrack.rawValue, forKey: Keys.ambientTrack) }
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
        static let reminderMode = "reminderMode"
        static let launchAtLogin = "launchAtLogin"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let enableSmartDetection = "enableSmartDetection"
        static let detectIdle = "detectIdle"
        static let detectVideoCall = "detectVideoCall"
        static let detectFullscreen = "detectFullscreen"
        static let detectScreenLock = "detectScreenLock"
        static let ambientTrack = "ambientTrack"
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
    init(defaults: UserDefaults = .standard) {
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
        reminderMode = ReminderMode(rawValue: defaults.string(forKey: Keys.reminderMode) ?? "") ?? .gentle
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        enableSmartDetection = defaults.object(forKey: Keys.enableSmartDetection) as? Bool ?? true
        detectIdle = defaults.object(forKey: Keys.detectIdle) as? Bool ?? true
        detectVideoCall = defaults.object(forKey: Keys.detectVideoCall) as? Bool ?? true
        detectFullscreen = defaults.object(forKey: Keys.detectFullscreen) as? Bool ?? true
        detectScreenLock = defaults.object(forKey: Keys.detectScreenLock) as? Bool ?? true
        ambientTrack = AmbientTrack(rawValue: defaults.string(forKey: Keys.ambientTrack) ?? "") ?? .off
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
        reminderMode = .gentle
        launchAtLogin = false
        enableSmartDetection = true
        detectIdle = true
        detectVideoCall = true
        detectFullscreen = true
        detectScreenLock = true
        ambientTrack = .off
        showRemainingMinutesInMenuBar = false
        appLanguage = .system
    }

    func validateSettings() -> Bool {
        Self.workDurationRange.contains(workDurationMinutes) && Self.restDurationSecondsRange.contains(restDurationSeconds)
    }
}
