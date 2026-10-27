import Foundation
import UserNotifications
import VivraLogging

/// One reminder to schedule, in app terms (so app-hosted tests never touch
/// package types).
struct ScheduledReminder: Equatable, Sendable {
    let identifier: String
    let fireDate: Date
    let title: String
    let body: String
}

protocol ReminderScheduling: Sendable {
    /// Asks for permission to notify. Returns whether it was granted.
    func authorize() async -> Bool
    /// Replaces every pending Vivra reminder with these.
    func replace(with reminders: [ScheduledReminder]) async
}

/// Local notifications only; nothing leaves the device. Text never contains
/// health data.
struct NotificationReminderScheduler: ReminderScheduling {
    static let prefix = "reminder."

    func authorize() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.app.failure("Notification authorization failed", code: (error as NSError).code)
            return false
        }
    }

    func replace(with reminders: [ScheduledReminder]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        )
        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let components = Calendar.autoupdatingCurrent.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: reminder.fireDate
            )
            let request = UNNotificationRequest(
                identifier: reminder.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            do {
                try await center.add(request)
            } catch {
                Log.app.failure("Reminder schedule failed", code: (error as NSError).code)
            }
        }
        Log.app.event("Reminders scheduled", count: reminders.count)
    }
}
