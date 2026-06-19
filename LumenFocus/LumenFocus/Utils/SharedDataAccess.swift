//
//  SharedDataAccess.swift
//  LumenFocus
//
//  App Group bridge for sharing today's statistics with the Widget extension.
//  Falls back to standard UserDefaults if the App Group entitlement isn't set up yet,
//  so the main app keeps working before the Widget target is added.
//

import Foundation

enum SharedDataAccess {
    /// 应用组标识符。新建 Widget target 时在「Signing & Capabilities」配置同名 App Group。
    static let appGroupID = "group.Yvette.LumenFocus"

    /// 共享 UserDefaults。App Group 未启用时降级到 standard
    static let defaults: UserDefaults = {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }()

    private enum Keys {
        static let todayRestCount = "shared.todayRestCount"
        static let todayWorkSeconds = "shared.todayWorkSeconds"
        static let currentStreak = "shared.currentStreak"
        static let weeklyBars = "shared.weeklyBars"
        static let updatedAt = "shared.updatedAt"
    }

    // MARK: - Main app writes

    /// 主 app 在 AppState 数据变化时调用，把今日数据写入共享区
    static func writeTodaySnapshot(restCount: Int, workSeconds: Int, currentStreak: Int, weeklyBars: [Int]) {
        defaults.set(restCount, forKey: Keys.todayRestCount)
        defaults.set(workSeconds, forKey: Keys.todayWorkSeconds)
        defaults.set(currentStreak, forKey: Keys.currentStreak)
        defaults.set(weeklyBars, forKey: Keys.weeklyBars)
        defaults.set(Date(), forKey: Keys.updatedAt)
    }

    // MARK: - Widget reads

    struct TodaySnapshot {
        let restCount: Int
        let workSeconds: Int
        let currentStreak: Int
        let weeklyBars: [Int]
        let updatedAt: Date?
    }

    static func readTodaySnapshot() -> TodaySnapshot {
        TodaySnapshot(
            restCount: defaults.integer(forKey: Keys.todayRestCount),
            workSeconds: defaults.integer(forKey: Keys.todayWorkSeconds),
            currentStreak: defaults.integer(forKey: Keys.currentStreak),
            weeklyBars: defaults.array(forKey: Keys.weeklyBars) as? [Int] ?? [],
            updatedAt: defaults.object(forKey: Keys.updatedAt) as? Date
        )
    }
}
