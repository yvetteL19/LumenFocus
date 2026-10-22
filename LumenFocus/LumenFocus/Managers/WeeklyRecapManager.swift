import Foundation
import UserNotifications

/// Weekly reminders remain disabled until a visible, explicit opt-in setting exists.
/// A future reminder must invite the user to open the live seven-day view rather
/// than repeating statistics captured when the notification was scheduled.
final class WeeklyRecapManager {
    static let shared = WeeklyRecapManager()
    private let identifier = "Yvette.LumenFocus.weeklyRecap"
    private lazy var center = UNUserNotificationCenter.current()

    private init() {}

    /// Also clears repeating notifications scheduled by older versions.
    func bootstrap() { cancelAll() }
    func reschedule() { cancelAll() }

    func cancelAll() {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
