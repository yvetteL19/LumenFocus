//
//  WeeklyRecapManager.swift
//  LumenFocus
//
//  Schedules a local notification every Sunday at 20:00 with the user's weekly
//  rest summary. Reschedules on app launch and after each day rollover.
//

import Foundation
import UserNotifications

final class WeeklyRecapManager {
    static let shared = WeeklyRecapManager()

    private let identifier = "Yvette.LumenFocus.weeklyRecap"
    private let center = UNUserNotificationCenter.current()

    private init() {}

    /// 在 app 启动时调用一次
    func bootstrap() {
        Task { await scheduleNextRecap() }
    }

    /// 显式重新调度（设置改变后调用）
    func reschedule() {
        Task { await scheduleNextRecap() }
    }

    /// 用户在设置中关闭后清掉
    func cancelAll() {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    // MARK: - Private

    private func scheduleNextRecap() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            Log.notifications.info("Weekly recap not scheduled: notifications not authorized")
            return
        }

        // 计算下一次周日 20:00 的统计快照
        let stats = StatisticsManager.shared
        let weeklyRestCount = stats.getWeeklyRestCount()
        let workSummary = stats.getWeeklyWorkDurationFormatted()
        let streak = stats.getCurrentStreak()

        let content = UNMutableNotificationContent()
        content.title = L("本周护眼总结")
        var body = String(format: L("护眼 %d 次 · 用眼 %@"), weeklyRestCount, workSummary)
        if streak > 0 {
            body += String(format: L(" · 连续 %d 天达标"), streak)
        }
        content.body = body
        content.sound = nil

        var dateComponents = DateComponents()
        dateComponents.weekday = 1   // 周日
        dateComponents.hour = 20
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        // 先取消旧的再调度新的，避免文案陈旧
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        do {
            try await center.add(request)
            Log.notifications.info("Weekly recap scheduled for Sunday 20:00")
        } catch {
            Log.notifications.error("Weekly recap schedule failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
