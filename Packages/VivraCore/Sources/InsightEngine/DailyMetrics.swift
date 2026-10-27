import Foundation
import VivraModel

/// One value per metric per day. A missing value means no data, except for
/// metrics logged only when they happen (`Metric.missingMeansZero`), which
/// read as zero between the first and last day with data.
public struct DailyMetrics: Sendable, Equatable {
    public private(set) var values: [Metric: [Day: Double]] = [:]
    private var spans: [Metric: ClosedRange<Day>] = [:]

    public func value(_ metric: Metric, on day: Day) -> Double? {
        if let value = values[metric]?[day] { return value }
        if metric.missingMeansZero, let span = spans[metric], span.contains(day) { return 0 }
        return nil
    }

    public func hasData(_ metric: Metric) -> Bool {
        !(values[metric]?.isEmpty ?? true)
    }

    mutating func set(_ metric: Metric, _ day: Day, _ value: Double) {
        values[metric, default: [:]][day] = value
    }

    mutating func add(_ metric: Metric, _ day: Day, _ value: Double) {
        values[metric, default: [:]][day, default: 0] += value
    }

    private mutating func finish() {
        for (metric, days) in values where metric.missingMeansZero {
            if let first = days.keys.min(), let last = days.keys.max() { spans[metric] = first...last }
        }
    }

    static let averageMetrics: [QuantityKind: Metric] = [
        .restingHeartRate: .restingHeartRate,
        .heartRateVariabilitySDNN: .heartRateVariability,
        .walkingHeartRateAverage: .walkingHeartRateAverage,
        .vo2Max: .vo2Max,
        .bodyMass: .weight,
        .bodyFatPercentage: .bodyFat,
        .respiratoryRate: .respiratoryRate,
        .oxygenSaturation: .bloodOxygen,
        .appleSleepingWristTemperature: .wristTemperature,
    ]

    static let cumulativeMetrics: [QuantityKind: Metric] = [
        .stepCount: .steps,
        .activeEnergyBurned: .activeEnergy,
        .appleExerciseTime: .exerciseMinutes,
        .distanceWalkingRunning: .distance,
        .dietaryEnergyConsumed: .dietaryEnergy,
        .dietaryProtein: .protein,
        .dietaryCarbohydrates: .carbohydrates,
        .dietaryFatTotal: .fat,
        .dietaryWater: .water,
        .dietaryCaffeine: .caffeine,
        .numberOfAlcoholicBeverages: .alcohol,
    ]

    public static func build(
        _ dataset: HealthDataset,
        calendar: DayCalendar,
        sourcePolicy: SourcePolicy = .default
    ) -> DailyMetrics {
        var metrics = DailyMetrics()

        for night in SleepNightBuilder.nights(from: dataset.sleepIntervals, calendar: calendar) {
            metrics.set(.sleepDuration, night.wakeDay, night.asleep)
        }

        // Averages.
        var sums: [Metric: [Day: (total: Double, count: Int)]] = [:]
        for sample in dataset.samples {
            guard let metric = averageMetrics[sample.kind] else { continue }
            let day = calendar.day(sample.start)
            let current = sums[metric]?[day] ?? (0, 0)
            sums[metric, default: [:]][day] = (current.total + sample.value, current.count + 1)
        }
        for (metric, days) in sums {
            for (day, sum) in days { metrics.set(metric, day, sum.total / Double(sum.count)) }
        }

        // Cumulative totals: largest source for activity, sum for intake.
        for (kind, days) in dataset.dailySourceTotals {
            guard let metric = cumulativeMetrics[kind] else { continue }
            for (day, bySource) in days {
                let own = bySource.filter { !sourcePolicy.isOwn($0.key) }.values
                guard !own.isEmpty else { continue }
                let value = kind.aggregation == .cumulativeActivity ? own.max()! : own.reduce(0, +)
                metrics.set(metric, day, value)
            }
        }

        // Category events.
        for event in dataset.categoryEvents {
            let day = calendar.day(event.start)
            switch event.kind {
            case .standHour where event.value == 0: metrics.add(.standHours, day, 1)
            case .mindfulSession: metrics.add(.mindfulMinutes, day, event.duration / 60)
            case .standHour, .irregularRhythm: break
            }
        }

        // Workouts.
        for workout in dataset.workouts where sourcePolicy.allows(workout) {
            let day = calendar.day(workout.start)
            metrics.add(.workoutMinutes, day, workout.duration / 60)
            metrics.add(.workoutCount, day, 1)
        }

        // Logs, and State of Mind not written by Vivra.
        var scales: [Metric: [Day: [Double]]] = [:]
        for state in dataset.statesOfMind where !sourcePolicy.isOwn(state.source.bundleIdentifier) {
            // Valence −1…1 onto the 1–5 mood scale.
            scales[.mood, default: [:]][calendar.day(state.date), default: []].append(3 + 2 * state.valence)
        }
        for log in dataset.logs {
            let day = calendar.day(log.timestamp)
            switch log.kind {
            case .mood: if let scale = log.scale { scales[.mood, default: [:]][day, default: []].append(Double(scale)) }
            case .energy:
                if let scale = log.scale { scales[.energyLevel, default: [:]][day, default: []].append(Double(scale)) }
            case .stress:
                if let scale = log.scale { scales[.stressLevel, default: [:]][day, default: []].append(Double(scale)) }
            case .drink:
                guard let drink = log.drink, let amount = log.amount else { continue }
                switch drink {
                case .water: metrics.add(.water, day, amount)
                case .coffee, .tea: metrics.add(.caffeine, day, amount)
                case .alcohol: metrics.add(.alcohol, day, amount)
                }
            case .meal, .note: break
            }
        }
        for (metric, days) in scales {
            for (day, values) in days { metrics.set(metric, day, Statistics.mean(values)!) }
        }

        metrics.finish()
        return metrics
    }
}
