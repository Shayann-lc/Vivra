import Foundation

/// The current time, injected so logic is testable with a fixed instant.
public protocol Clock: Sendable {
    var now: Date { get }
}

public struct FixedClock: Clock {
    public let now: Date

    public init(_ now: Date) {
        self.now = now
    }
}

/// A calendar with an explicit time zone. Core logic takes one of these
/// instead of reading `Calendar.current`.
public struct DayCalendar: Sendable {
    public let calendar: Calendar

    public init(timeZone: TimeZone, identifier: Calendar.Identifier = .gregorian) {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    public init(_ calendar: Calendar) {
        self.calendar = calendar
    }

    public var timeZone: TimeZone { calendar.timeZone }

    public func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    public func day(_ date: Date) -> Day {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return Day(year: components.year!, month: components.month!, day: components.day!)
    }

    public func start(of day: Day) -> Date {
        calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day))!
    }

    public func adding(days: Int, to day: Day) -> Day {
        self.day(calendar.date(byAdding: .day, value: days, to: start(of: day))!)
    }

    public func adding(hours: Int, to date: Date) -> Date {
        calendar.date(byAdding: .hour, value: hours, to: date)!
    }
}

/// A calendar day, independent of time zone once constructed.
public struct Day: Codable, Sendable, Hashable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (lhs: Day, rhs: Day) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}
