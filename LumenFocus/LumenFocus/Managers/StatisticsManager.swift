//
//  StatisticsManager.swift
//  LumenFocus
//
//  Created by AI Director on 2026/2/4.
//  Enhanced statistics tracking with weekly data
//

import Foundation

/// 每日统计数据结构
struct DailyStatistics: Codable {
    var date: String  // 格式: yyyy-MM-dd
    var restCount: Int  // 护眼次数
    var workDuration: Int  // 用眼时长（秒）

    init(date: String, restCount: Int = 0, workDuration: Int = 0) {
        self.date = date
        self.restCount = restCount
        self.workDuration = workDuration
    }
}

/// 统计管理器 - 负责统计数据的持久化和计算
class StatisticsManager {
    static let shared = StatisticsManager()

    // MARK: - Private Properties

    private let userDefaults = UserDefaults.standard
    private let statisticsKey = "dailyStatisticsData"

    // MARK: - Initialization

    private init() {
        // 迁移旧数据（如果存在）
        migrateOldDataIfNeeded()
    }

    // MARK: - Public Methods

    /// 获取今日统计
    func getTodayStatistics() -> DailyStatistics {
        let today = getTodayKey()
        return getStatistics(for: today)
    }

    /// 更新今日统计
    func updateTodayStatistics(restCount: Int, workDuration: Int) {
        let today = getTodayKey()
        var stats = getStatistics(for: today)
        stats.restCount = restCount
        stats.workDuration = workDuration
        saveStatistics(stats)
    }

    /// 增加今日护眼次数
    func incrementTodayRestCount() {
        var stats = getTodayStatistics()
        stats.restCount += 1
        saveStatistics(stats)
    }

    /// 增加今日用眼时长（秒）
    func incrementTodayWorkDuration(seconds: Int = 1) {
        var stats = getTodayStatistics()
        stats.workDuration += seconds
        saveStatistics(stats)
    }

    /// 获取本周统计数据（最近7天）
    func getWeeklyStatistics() -> [DailyStatistics] {
        let calendar = Calendar.current
        let today = Date()
        var weeklyStats: [DailyStatistics] = []

        // 获取最近7天的数据
        for dayOffset in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) {
                let dateKey = formatDate(date)
                let stats = getStatistics(for: dateKey)
                weeklyStats.append(stats)
            }
        }

        return weeklyStats.reversed()  // 按时间顺序排列
    }

    /// 获取本周护眼总次数
    func getWeeklyRestCount() -> Int {
        return getWeeklyStatistics().reduce(0) { $0 + $1.restCount }
    }

    /// 获取本周用眼总时长（秒）
    func getWeeklyWorkDuration() -> Int {
        return getWeeklyStatistics().reduce(0) { $0 + $1.workDuration }
    }

    /// 获取本周用眼总时长（格式化字符串，本地化）
    func getWeeklyWorkDurationFormatted() -> String {
        return formatWorkDuration(getWeeklyWorkDuration())
    }

    /// 获取每日平均护眼次数
    func getDailyAverageRestCount() -> Int {
        let weeklyStats = getWeeklyStatistics()
        let daysWithData = weeklyStats.filter { $0.restCount > 0 }.count
        guard daysWithData > 0 else { return 0 }

        let totalCount = weeklyStats.reduce(0) { $0 + $1.restCount }
        return totalCount / daysWithData
    }

    // MARK: - Streak

    /// 每日「达标」所需的最少护眼次数（streak 用）
    var dailyStreakThreshold: Int { 4 }

    /// 当前连续达标天数（含今日）。今日尚未达标但昨天达标 → 仍计入昨天延续的 streak
    func getCurrentStreak() -> Int {
        let calendar = Calendar.current
        var date = Date()
        var streak = 0
        let todayKey = formatDate(date)
        let todayStats = getStatistics(for: todayKey)

        // 如果今天还没达标，先看昨天起算
        if todayStats.restCount < dailyStreakThreshold {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: date) else { return 0 }
            date = yesterday
        }

        // 向前扫描，直到遇到未达标的一天
        while true {
            let key = formatDate(date)
            let stats = getStatistics(for: key)
            if stats.restCount >= dailyStreakThreshold {
                streak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: date) else { break }
                date = prev
            } else {
                break
            }
            // 防御性上限：扫到 365 天之外停止
            if streak >= 365 { break }
        }
        return streak
    }

    /// 获取最近 N 天的统计（按日期升序）
    func getRecentStatistics(days: Int) -> [DailyStatistics] {
        let calendar = Calendar.current
        let today = Date()
        var result: [DailyStatistics] = []
        for offset in (0..<days).reversed() {
            if let date = calendar.date(byAdding: .day, value: -offset, to: today) {
                let key = formatDate(date)
                result.append(getStatistics(for: key))
            }
        }
        return result
    }

    /// 已记录的全部统计（按日期升序）
    func getAllStatistics() -> [DailyStatistics] {
        loadAllStatistics().sorted { $0.date < $1.date }
    }

    /// 历史上最长的连续达标天数（扫描所有已记录数据）
    func getLongestStreak() -> Int {
        let all = loadAllStatistics()
        guard !all.isEmpty else { return 0 }

        let calendar = Calendar.current
        // 按日期排序
        let sortedDates = all.compactMap { stats -> Date? in
            guard stats.restCount >= dailyStreakThreshold else { return nil }
            return parseDate(stats.date)
        }.sorted()

        guard !sortedDates.isEmpty else { return 0 }

        var longest = 1
        var current = 1

        for i in 1..<sortedDates.count {
            let prev = sortedDates[i - 1]
            let curr = sortedDates[i]
            if let days = calendar.dateComponents([.day], from: prev, to: curr).day, days == 1 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }

    /// 清理过期数据（保留最近30天）
    func cleanupOldData() {
        let calendar = Calendar.current
        let today = Date()
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today)!

        var allStats = loadAllStatistics()

        // 过滤掉30天前的数据
        allStats = allStats.filter { stats in
            if let date = parseDate(stats.date) {
                return date >= thirtyDaysAgo
            }
            return false
        }

        saveAllStatistics(allStats)
    }

    // MARK: - Private Methods

    /// 获取指定日期的统计数据
    private func getStatistics(for dateKey: String) -> DailyStatistics {
        let allStats = loadAllStatistics()
        return allStats.first(where: { $0.date == dateKey }) ?? DailyStatistics(date: dateKey)
    }

    /// 保存统计数据
    private func saveStatistics(_ stats: DailyStatistics) {
        var allStats = loadAllStatistics()

        // 更新或添加
        if let index = allStats.firstIndex(where: { $0.date == stats.date }) {
            allStats[index] = stats
        } else {
            allStats.append(stats)
        }

        saveAllStatistics(allStats)
    }

    /// 加载所有统计数据
    private func loadAllStatistics() -> [DailyStatistics] {
        guard let data = userDefaults.data(forKey: statisticsKey),
              let stats = try? JSONDecoder().decode([DailyStatistics].self, from: data) else {
            return []
        }
        return stats
    }

    /// 保存所有统计数据
    private func saveAllStatistics(_ stats: [DailyStatistics]) {
        if let data = try? JSONEncoder().encode(stats) {
            userDefaults.set(data, forKey: statisticsKey)
        }
    }

    /// 获取今日Key（格式：yyyy-MM-dd）
    private func getTodayKey() -> String {
        return formatDate(Date())
    }

    /// 格式化日期为Key
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// 解析日期Key
    private func parseDate(_ dateKey: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateKey)
    }

    /// 迁移旧数据（兼容AppState的旧存储方式）
    private func migrateOldDataIfNeeded() {
        let todayKey = getTodayKey()

        // 检查是否已经迁移过
        if userDefaults.bool(forKey: "hasMigratedToStatisticsManager") {
            return
        }

        // 从AppState的旧Key中读取今日数据
        let oldRestCount = userDefaults.integer(forKey: "restCount_\(todayKey)")
        let oldWorkDuration = userDefaults.integer(forKey: "workDuration_\(todayKey)")

        if oldRestCount > 0 || oldWorkDuration > 0 {
            // 迁移数据
            updateTodayStatistics(restCount: oldRestCount, workDuration: oldWorkDuration)
        }

        // 标记为已迁移
        userDefaults.set(true, forKey: "hasMigratedToStatisticsManager")
    }
}
