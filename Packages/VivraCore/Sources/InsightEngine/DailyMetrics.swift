import Foundation
import VivraModel

/// Per-day values the engine works from. A missing key means no data.
public struct DailyMetrics: Sendable, Equatable {
    public var values: [Metric: [Day: Double]] = [:]
    /// Days covered by workout data. Workouts are a count, so a day with no
    /// workouts is a 0, not missing, once the person has any workout data.
    public var hasWorkoutData = false

    public func value(_ metric: Metric, on day: Day) -> Double? {
        values[metric]?[day]
    }

    public static func build(
        sleepNights: [SleepNight],
        samples: [QuantitySample],
        workouts: [Workout],
        calendar: DayCalendar
    ) -> DailyMetrics {
        var metrics = DailyMetrics()
        for night in sleepNights {
            metrics.values[.sleepDuration, default: [:]][night.wakeDay] = night.asleep
        }

        let quantityMetrics: [QuantityKind: Metric] = [
            .restingHeartRate: .restingHeartRate,
            .heartRateVariabilitySDNN: .heartRateVariability,
            .walkingHeartRateAverage: .walkingHeartRateAverage,
            .vo2Max: .vo2Max,
        ]
        var sums: [Metric: [Day: (total: Double, count: Int)]] = [:]
        for sample in samples {
            guard let metric = quantityMetrics[sample.kind] else { continue }
            let day = calendar.day(sample.start)
            let current = sums[metric]?[day] ?? (0, 0)
            sums[metric, default: [:]][day] = (current.total + sample.value, current.count + 1)
        }
        for (metric, days) in sums {
            metrics.values[metric] = days.mapValues { $0.total / Double($0.count) }
        }

        metrics.hasWorkoutData = !workouts.isEmpty
        for workout in workouts {
            let day = calendar.day(workout.start)
            metrics.values[.workoutMinutes, default: [:]][day, default: 0] += workout.duration / 60
            metrics.values[.workoutCount, default: [:]][day, default: 0] += 1
        }
        return metrics
    }
}
