import Foundation
import Security

/// Optional bridge for a future Widget target. The main app's repository never
/// depends on an App Group and does not mirror statistics every timer tick.
enum SharedDataAccess {
    static let appGroupID = "group.Yvette.LumenFocus"

    /// Creating a suite without the signing entitlement can cause system warnings.
    /// Check the signed entitlement first; no fallback writes to standard defaults.
    private static let defaults: UserDefaults? = {
        guard let task = SecTaskCreateFromSelf(nil),
              let groups = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil) as? [String],
              groups.contains(appGroupID) else { return nil }
        return UserDefaults(suiteName: appGroupID)
    }()

    private enum Keys {
        static let todayRestCount = "shared.todayRestCount"
        static let todayWorkSeconds = "shared.todayWorkSeconds"
        static let currentStreak = "shared.currentStreak"
        static let weeklyBars = "shared.weeklyBars"
        static let updatedAt = "shared.updatedAt"
    }

    static func writeTodaySnapshot(restCount: Int, workSeconds: Int, currentStreak: Int, weeklyBars: [Int]) {
        guard let defaults else { return }
        defaults.set(restCount, forKey: Keys.todayRestCount)
        defaults.set(workSeconds, forKey: Keys.todayWorkSeconds)
        defaults.set(currentStreak, forKey: Keys.currentStreak)
        defaults.set(weeklyBars, forKey: Keys.weeklyBars)
        defaults.set(Date(), forKey: Keys.updatedAt)
    }

    struct TodaySnapshot {
        let restCount: Int
        let workSeconds: Int
        let currentStreak: Int
        let weeklyBars: [Int]
        let updatedAt: Date?
    }

    static func readTodaySnapshot() -> TodaySnapshot {
        TodaySnapshot(
            restCount: defaults?.integer(forKey: Keys.todayRestCount) ?? 0,
            workSeconds: defaults?.integer(forKey: Keys.todayWorkSeconds) ?? 0,
            currentStreak: defaults?.integer(forKey: Keys.currentStreak) ?? 0,
            weeklyBars: defaults?.array(forKey: Keys.weeklyBars) as? [Int] ?? [],
            updatedAt: defaults?.object(forKey: Keys.updatedAt) as? Date
        )
    }
}
