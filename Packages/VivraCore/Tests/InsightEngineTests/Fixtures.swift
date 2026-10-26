import Foundation
import VivraModel

@testable import InsightEngine

enum Fixtures {
    static let utc = DayCalendar(timeZone: TimeZone(identifier: "UTC")!)
    static let watch = SourceInfo(bundleIdentifier: "com.apple.health.watch", name: "Apple Watch")
    static let phone = SourceInfo(bundleIdentifier: "com.apple.health.phone", name: "iPhone")
    static let strava = SourceInfo(bundleIdentifier: "com.strava.stravaride", name: "Strava")

    /// "Today" in the tests: 2026-04-01, 10:00 UTC.
    static let today = Day(year: 2026, month: 4, day: 1)
    static var now: Date { utc.start(of: today).addingTimeInterval(10 * 3600) }

    static func date(_ day: Day, hour: Double) -> Date {
        utc.start(of: day).addingTimeInterval(hour * 3600)
    }

    static func daysAgo(_ count: Int) -> Day {
        utc.adding(days: -count, to: today)
    }

    static func sleep(
        wakeDay: Day,
        hours: Double,
        stage: SleepStage = .core,
        source: SourceInfo = watch
    ) -> SleepInterval {
        let end = date(wakeDay, hour: 7)
        return SleepInterval(
            id: UUID(), stage: stage, start: end.addingTimeInterval(-hours * 3600), end: end, source: source)
    }

    static func quantity(_ kind: QuantityKind, day: Day, value: Double) -> QuantitySample {
        let time = date(day, hour: 8)
        return QuantitySample(id: UUID(), kind: kind, start: time, end: time, value: value, source: watch)
    }

    static func workout(day: Day, minutes: Double, source: SourceInfo = watch) -> Workout {
        let start = date(day, hour: 17)
        return Workout(
            id: UUID(),
            activityType: 37,
            start: start,
            end: start.addingTimeInterval(minutes * 60),
            duration: minutes * 60,
            activeEnergyKilocalories: nil,
            distanceMeters: nil,
            source: source
        )
    }
}
