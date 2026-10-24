import Foundation

/// Unsubmitted changes never write preferences. Dropping this value cancels setup.
struct OnboardingDraft: Equatable {
    var workMinutes: Int
    var restSeconds: Int
    var reminderMode: ReminderMode
    var launchAtLogin: Bool

    init(settings: AppSettings, launchAtLogin: Bool) {
        workMinutes = settings.workDurationMinutes
        restSeconds = settings.restDurationSeconds
        reminderMode = settings.reminderMode
        self.launchAtLogin = launchAtLogin
    }

    /// A failed system preference leaves the cadence and completion flag untouched.
    /// The caller refreshes the switch from the actual system value before retrying.
    func commit(to settings: AppSettings,
                readLaunchAtLogin: () -> Bool,
                setLaunchAtLogin: (Bool) -> Bool) -> Bool {
        guard AppSettings.workDurationRange.contains(workMinutes),
              AppSettings.restDurationSecondsRange.contains(restSeconds) else { return false }
        if readLaunchAtLogin() != launchAtLogin {
            guard setLaunchAtLogin(launchAtLogin), readLaunchAtLogin() == launchAtLogin else { return false }
        }
        settings.workDurationMinutes = workMinutes
        settings.restDurationSeconds = restSeconds
        settings.reminderMode = reminderMode
        settings.launchAtLogin = readLaunchAtLogin()
        settings.hasCompletedOnboarding = true
        return true
    }
}
