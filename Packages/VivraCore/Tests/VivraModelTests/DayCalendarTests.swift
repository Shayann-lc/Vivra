import Foundation
import Testing

@testable import VivraModel

@Suite struct DayCalendarTests {
    private let london = DayCalendar(timeZone: TimeZone(identifier: "Europe/London")!)

    @Test func dayUsesTheCalendarsTimeZone() {
        // 2026-06-01 23:30 UTC is already 2 June in London (BST).
        let date = Date(timeIntervalSince1970: 1_780_356_600)
        #expect(london.day(date) == Day(year: 2026, month: 6, day: 2))
    }

    @Test func addingDaysCrossesMonthsAndDaylightSaving() {
        let day = Day(year: 2026, month: 3, day: 28)
        #expect(london.adding(days: 4, to: day) == Day(year: 2026, month: 4, day: 1))
        #expect(london.adding(days: -28, to: day) == Day(year: 2026, month: 2, day: 28))
    }

    @Test func daysOrderChronologically() {
        #expect(Day(year: 2025, month: 12, day: 31) < Day(year: 2026, month: 1, day: 1))
        #expect(Day(year: 2026, month: 1, day: 2).description == "2026-01-02")
    }
}
