import Foundation
import VivraModel

/// When to remind, and what to say. At most one reminder a day, none once
/// today's goal is met, scheduled `daysAhead` days at a time so reminders
/// stop by themselves after a week without opening the app.
public enum ReminderPlan {
    public static let daysAhead = 7
    public static let defaultMinutes = 19 * 60

    public static let title = "Vivra"
    /// No numbers, no health data, no pressure.
    public static let messages = [
        "A moment to check in? It takes a few seconds.",
        "How's today going? Quick Log is ready when you are.",
        "Time for a quick check-in, if you'd like.",
    ]

    public struct Reminder: Sendable, Equatable {
        public let day: Day
        public let fireDate: Date
        public let message: String
        public var identifier: String { "reminder.\(day)" }
    }

    /// `minutes` after midnight, in the calendar's time zone.
    public static func plan(
        minutes: Int,
        goalMetToday: Bool,
        clock: any Clock,
        calendar: DayCalendar
    ) -> [Reminder] {
        let today = calendar.day(clock.now)
        return (0..<daysAhead).compactMap { offset in
            let day = calendar.adding(days: offset, to: today)
            let start = calendar.start(of: day)
            guard
                let fireDate = calendar.calendar.date(
                    bySettingHour: minutes / 60,
                    minute: minutes % 60,
                    second: 0,
                    of: start
                )
            else { return nil }
            if offset == 0 && (goalMetToday || fireDate <= clock.now) { return nil }
            return Reminder(day: day, fireDate: fireDate, message: message(for: day))
        }
    }

    /// Rotates through `messages` by date, so the same day always gets the
    /// same message.
    static func message(for day: Day) -> String {
        let ordinal = day.year * 372 + day.month * 31 + day.day
        return messages[ordinal % messages.count]
    }
}
