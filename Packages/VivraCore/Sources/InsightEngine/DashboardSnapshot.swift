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

    public struct ActivityDay: Sendable, Equatable, Identifiable {
        public let day: Day
        public let steps: Double?
        public let exerciseMinutes: Double?
        public var id: Day { day }
    }

    public struct Reading: Sendable, Equatable {
        public let day: Day
        public let value: Double
    }

    /// Oldest first, ending today.
    public let days: [Day]
    /// Only days with sleep data.
    public let sleep: [SleepDay]
    /// Only days with resting heart rate or HRV.
    public let heart: [HeartDay]
    /// Only days with steps or exercise.
    public let activity: [ActivityDay]
    /// Newest first, from every source.
    public let workouts: [Workout]
    /// Today's totals so far (water, caffeine, alcohol), Health and logs combined.
    public let todayIntake: [Metric: Double]
    /// Today's logged mood, energy and stress (averaged if logged more than once).
    public let todayLogged: [Metric: Double]
    /// The most recent body measurement in the window.
    public let latestBody: [Metric: Reading]

    public static let dayCount = 7
    static let intakeMetrics: [Metric] = [.water, .caffeine, .alcohol]
    static let loggedMetrics: [Metric] = [.mood, .energyLevel, .stressLevel]
    static let bodyMetrics: [Metric] = [.weight, .bodyFat, .respiratoryRate, .bloodOxygen, .wristTemperature]

    /// The first and last day to load data for.
    public static func loadDays(clock: any Clock, calendar: DayCalendar) -> (first: Day, last: Day) {
        let today = calendar.day(clock.now)
        return (calendar.adding(days: -(dayCount - 1), to: today), today)
    }

    public static func build(
        _ dataset: HealthDataset,
        clock: any Clock,
        calendar: DayCalendar,
        sourcePolicy: SourcePolicy = .includeAll
    ) -> DashboardSnapshot {
        let today = calendar.day(clock.now)
        let days = (0..<dayCount).reversed().map { calendar.adding(days: -$0, to: today) }
        let window = Set(days)
        let nights = SleepNightBuilder.nights(from: dataset.sleepIntervals, calendar: calendar)
        let metrics = DailyMetrics.build(dataset, calendar: calendar, sourcePolicy: sourcePolicy)

        let sleep = nights.filter { window.contains($0.wakeDay) }.map {
            SleepDay(day: $0.wakeDay, asleep: $0.asleep, stages: $0.stages)
        }
        let heart = days.compactMap { day -> HeartDay? in
            let resting = metrics.value(.restingHeartRate, on: day)
            let variability = metrics.value(.heartRateVariability, on: day)
            guard resting != nil || variability != nil else { return nil }
            return HeartDay(day: day, restingHeartRate: resting, heartRateVariability: variability)
        }
        let activity = days.compactMap { day -> ActivityDay? in
            let steps = metrics.value(.steps, on: day)
            let exercise = metrics.value(.exerciseMinutes, on: day)
            guard steps != nil || exercise != nil else { return nil }
            return ActivityDay(day: day, steps: steps, exerciseMinutes: exercise)
        }
        let recentWorkouts =
            dataset.workouts
            .filter { window.contains(calendar.day($0.start)) }
            .sorted { $0.start > $1.start }

        var todayIntake: [Metric: Double] = [:]
        for metric in intakeMetrics { todayIntake[metric] = metrics.values[metric]?[today] }
        var todayLogged: [Metric: Double] = [:]
        for metric in loggedMetrics { todayLogged[metric] = metrics.values[metric]?[today] }
        var latestBody: [Metric: Reading] = [:]
        for metric in bodyMetrics {
            if let day = days.last(where: { metrics.values[metric]?[$0] != nil }) {
                latestBody[metric] = Reading(day: day, value: metrics.values[metric]![day]!)
            }
        }

        return DashboardSnapshot(
            days: days,
            sleep: sleep,
            heart: heart,
            activity: activity,
            workouts: recentWorkouts,
            todayIntake: todayIntake,
            todayLogged: todayLogged,
            latestBody: latestBody
        )
    }
}
