import Foundation
import VivraModel

/// Everything the engine reads, loaded for a date range.
public struct HealthDataset: Sendable {
    public var sleepIntervals: [SleepInterval]
    /// Samples of `.average` kinds. (Cumulative kinds come as totals.)
    public var samples: [QuantitySample]
    /// Per-day, per-source totals of cumulative kinds, keyed by source
    /// bundle identifier.
    public var dailySourceTotals: DailySourceTotals
    public var workouts: [Workout]
    public var categoryEvents: [CategoryEvent]
    public var statesOfMind: [StateOfMindSample]
    public var logs: [LogEntry]

    public init(
        sleepIntervals: [SleepInterval] = [],
        samples: [QuantitySample] = [],
        dailySourceTotals: DailySourceTotals = [:],
        workouts: [Workout] = [],
        categoryEvents: [CategoryEvent] = [],
        statesOfMind: [StateOfMindSample] = [],
        logs: [LogEntry] = []
    ) {
        self.sleepIntervals = sleepIntervals
        self.samples = samples
        self.dailySourceTotals = dailySourceTotals
        self.workouts = workouts
        self.categoryEvents = categoryEvents
        self.statesOfMind = statesOfMind
        self.logs = logs
    }

    /// The quantity kinds loaded as raw samples, and those loaded as totals.
    public static let averageKinds = QuantityKind.allCases.filter { $0.aggregation == .average && $0 != .heartRate }
    public static let cumulativeKinds = QuantityKind.allCases.filter { $0.aggregation != .average }
}

public typealias DailySourceTotals = [QuantityKind: [Day: [String: Double]]]

extension Dictionary where Key == QuantityKind, Value == [Day: [String: Double]] {
    /// Builds totals from raw samples, attributing each to the day it starts.
    /// The repository computes the same thing in SQL; this is the reference.
    public static func totals(from samples: [QuantitySample], calendar: DayCalendar) -> DailySourceTotals {
        var totals: DailySourceTotals = [:]
        for sample in samples where sample.kind.aggregation != .average {
            totals[sample.kind, default: [:]][calendar.day(sample.start), default: [:]][
                sample.source.bundleIdentifier, default: 0
            ] += sample.value
        }
        return totals
    }
}

/// Which sources feed reports (and so the on-device model). The dashboard
/// always shows everything.
public struct SourcePolicy: Sendable, Equatable {
    /// Workouts from sources whose bundle identifier starts with one of these
    /// are left out of reports.
    public var excludedWorkoutSourcePrefixes: [String]
    /// Vivra's own bundle identifier. Samples Vivra wrote to Apple Health
    /// (write-back) are ignored when read back, because the log entry they
    /// came from is already counted.
    public var ownBundleIdentifier: String?

    public init(excludedWorkoutSourcePrefixes: [String], ownBundleIdentifier: String? = nil) {
        self.excludedWorkoutSourcePrefixes = excludedWorkoutSourcePrefixes
        self.ownBundleIdentifier = ownBundleIdentifier
    }

    /// Strava-sourced workouts are excluded from reports until the owner
    /// confirms Strava's API terms don't reach HealthKit copies (PLAN §8).
    /// Use `.includeAll` to change that.
    public static let `default` = SourcePolicy(excludedWorkoutSourcePrefixes: ["com.strava"])
    public static let includeAll = SourcePolicy(excludedWorkoutSourcePrefixes: [])

    public func withOwnBundleIdentifier(_ identifier: String?) -> SourcePolicy {
        SourcePolicy(excludedWorkoutSourcePrefixes: excludedWorkoutSourcePrefixes, ownBundleIdentifier: identifier)
    }

    func allows(_ workout: Workout) -> Bool {
        !excludedWorkoutSourcePrefixes.contains { workout.source.bundleIdentifier.hasPrefix($0) }
    }

    func isOwn(_ bundleIdentifier: String) -> Bool {
        bundleIdentifier == ownBundleIdentifier
    }
}
