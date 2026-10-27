import Foundation
import VivraModel

/// What the dashboard shows: the last 7 days, today included.
public struct DashboardSnapshot: Sendable, Equatable {
    public struct SleepDay: Sendable, Equatable, Identifiable {
        public let day: Day
        public let asleep: TimeInterval
        public let stages: [SleepStage: TimeInterval]
        public var id: Day { day }
    }

    public struct HeartDay: Sendable, Equatable, Identifiable {
        public let day: Day
        public let restingHeartRate: Double?
        public let heartRateVariability: Double?
        public var id: Day { day }
    }

    /// Oldest first, ending today.
    public let days: [Day]
    /// Only days with sleep data.
    public let sleep: [SleepDay]
    /// Only days with resting heart rate or HRV.
    public let heart: [HeartDay]
    /// Newest first, from every source.
    public let workouts: [Workout]

    public static let dayCount = 7

    /// The date range to load data for.
    public static func loadRange(clock: any Clock, calendar: DayCalendar) -> (start: Date, end: Date) {
        let today = calendar.day(clock.now)
        // Sleep for the first day can end as early as 18:00 the day before.
        let start = calendar.start(of: calendar.adding(days: -dayCount, to: today))
        let end = calendar.start(of: calendar.adding(days: 1, to: today))
        return (start, end)
    }

    public static func build(
        sleepIntervals: [SleepInterval],
        samples: [QuantitySample],
        workouts: [Workout],
        clock: any Clock,
        calendar: DayCalendar
    ) -> DashboardSnapshot {
        let today = calendar.day(clock.now)
        let days = (0..<dayCount).reversed().map { calendar.adding(days: -$0, to: today) }
        let window = Set(days)

        let nights = SleepNightBuilder.nights(from: sleepIntervals, calendar: calendar)
        let metrics = DailyMetrics.build(HealthDataset(samples: samples), calendar: calendar)

        let sleep = nights.filter { window.contains($0.wakeDay) }.map {
            SleepDay(day: $0.wakeDay, asleep: $0.asleep, stages: $0.stages)
        }
        let heart = days.compactMap { day -> HeartDay? in
            let resting = metrics.value(.restingHeartRate, on: day)
            let variability = metrics.value(.heartRateVariability, on: day)
            guard resting != nil || variability != nil else { return nil }
            return HeartDay(day: day, restingHeartRate: resting, heartRateVariability: variability)
        }
        let recentWorkouts =
            workouts
            .filter { window.contains(calendar.day($0.start)) }
            .sorted { $0.start > $1.start }

        return DashboardSnapshot(days: days, sleep: sleep, heart: heart, workouts: recentWorkouts)
    }
}
