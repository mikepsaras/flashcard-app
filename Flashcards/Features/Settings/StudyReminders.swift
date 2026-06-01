import Foundation
import UserNotifications

/// Opt-in daily local notification reminding the user to review. Off by default;
/// permission is requested only when the user turns it on. Notifications stay on-device.
@MainActor
enum StudyReminders {
    static let identifier = "daily-study-reminder"

    /// Requests notification permission, returning whether it was granted.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// (Re)schedules the daily reminder at the given time, replacing any existing one.
    static func schedule(hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "Time to review"
        content.body = "Your flashcards are waiting — keep your streak going."
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
