import Foundation
import VivraModel

/// Which sources feed reports (and so the on-device model). The dashboard
/// always shows everything.
public struct SourcePolicy: Sendable, Equatable {
    /// Workouts from sources whose bundle identifier starts with one of these
    /// are left out of reports.
    public var excludedWorkoutSourcePrefixes: [String]

    public init(excludedWorkoutSourcePrefixes: [String]) {
        self.excludedWorkoutSourcePrefixes = excludedWorkoutSourcePrefixes
    }

    /// Strava-sourced workouts are excluded from reports until the owner
    /// confirms Strava's API terms don't reach HealthKit copies (PLAN §8).
    /// Switch to `.includeAll` to change that.
    public static let `default` = SourcePolicy(excludedWorkoutSourcePrefixes: ["com.strava"])
    public static let includeAll = SourcePolicy(excludedWorkoutSourcePrefixes: [])

    func allows(_ workout: Workout) -> Bool {
        !excludedWorkoutSourcePrefixes.contains { workout.source.bundleIdentifier.hasPrefix($0) }
    }
}

/// Thresholds for showing anything. Kept together so they're easy to review.
public enum PatternRules {
    /// A weekly average needs this many days with data.
    public static let minimumDaysPerWeek = 3
    /// Each side of a comparison needs this many days...
    public static let minimumDaysPerGroup = 7
    /// ...and both sides together this many.
    public static let minimumPairedDays = 14
    /// Benjamini–Hochberg false discovery rate.
    public static let falseDiscoveryRate = 0.10
    /// Days of history patterns look at.
    public static let patternWindowDays = 90
    /// A "workout day" has at least this many workout minutes.
    public static let workoutDayMinutes = 20.0
    public static let resamples = 2_000
    public static let seed: UInt64 = 0x5EED_0F_71F4

    /// Differences smaller than this aren't reported even if significant.
    static func minimumEffect(_ metric: Metric) -> Double {
        switch metric {
        case .restingHeartRate, .walkingHeartRateAverage: 1
        case .heartRateVariability: 3
        case .sleepDuration: 15 * 60
        case .vo2Max: 1
        case .workoutMinutes: 10
        case .workoutCount: 1
        }
    }

    /// Resting heart rate outside this weekly average range gets the
    /// "consider talking with a professional" note. The American Heart
    /// Association gives 60–100 bpm as a normal adult resting rate and notes
    /// that very fit people are often lower, so the lower bound is set at 40.
    static let typicalRestingHeartRate = 40.0...100.0
}

public enum WeeklyReportBuilder {
    /// Builds the report for the 7 complete days before `clock.now`.
    public static func build(
        sleepIntervals: [SleepInterval],
        samples: [QuantitySample],
        workouts: [Workout],
        clock: any Clock,
        calendar: DayCalendar,
        sourcePolicy: SourcePolicy = .default
    ) -> WeeklyReport {
        let nights = SleepNightBuilder.nights(from: sleepIntervals, calendar: calendar)
        let metrics = DailyMetrics.build(
            sleepNights: nights,
            samples: samples,
            workouts: workouts.filter(sourcePolicy.allows),
            calendar: calendar
        )
        let today = calendar.day(clock.now)
        let thisWeek = (1...7).map { calendar.adding(days: -$0, to: today) }
        let previousWeek = (8...14).map { calendar.adding(days: -$0, to: today) }

        let patterns = patternFindings(metrics: metrics, today: today, calendar: calendar)
        let weekly = weeklyFindings(metrics: metrics, thisWeek: thisWeek, previousWeek: previousWeek)

        return WeeklyReport(
            periodStart: thisWeek.last!,
            periodEnd: thisWeek.first!,
            findings: patterns + weekly
        )
    }

    // MARK: Weekly averages

    static func weeklyFindings(metrics: DailyMetrics, thisWeek: [Day], previousWeek: [Day]) -> [Finding] {
        var findings: [Finding] = []
        for metric in [
            Metric.sleepDuration, .restingHeartRate, .heartRateVariability, .walkingHeartRateAverage, .vo2Max,
        ] {
            let current = thisWeek.compactMap { metrics.value(metric, on: $0) }
            guard current.count >= PatternRules.minimumDaysPerWeek else { continue }
            let previous = previousWeek.compactMap { metrics.value(metric, on: $0) }
            let average = WeeklyAverage(
                metric: metric,
                thisWeek: Statistics.mean(current)!,
                thisWeekDays: current.count,
                previousWeek: previous.count >= PatternRules.minimumDaysPerWeek ? Statistics.mean(previous) : nil,
                previousWeekDays: previous.count
            )
            let outsideTypical =
                metric == .restingHeartRate && !PatternRules.typicalRestingHeartRate.contains(average.thisWeek)
            findings.append(
                Finding(
                    id: "weekly.\(metric.rawValue)", detail: .weeklyAverage(average),
                    suggestProfessional: outsideTypical)
            )
        }

        if metrics.hasWorkoutData {
            for metric in [Metric.workoutCount, .workoutMinutes] {
                let total = { (days: [Day]) in days.reduce(0) { $0 + (metrics.value(metric, on: $1) ?? 0) } }
                let average = WeeklyAverage(
                    metric: metric,
                    thisWeek: total(thisWeek),
                    thisWeekDays: 7,
                    previousWeek: total(previousWeek),
                    previousWeekDays: 7
                )
                findings.append(Finding(id: "weekly.\(metric.rawValue)", detail: .weeklyAverage(average)))
            }
        }
        return findings
    }

    // MARK: Patterns

    private struct Candidate {
        let id: String
        let condition: Condition
        let threshold: Double
        let outcome: Metric
        let with: [Double]
        let without: [Double]
        let pValue: Double
    }

    static func patternFindings(metrics: DailyMetrics, today: Day, calendar: DayCalendar) -> [Finding] {
        let window = (1...PatternRules.patternWindowDays).map { calendar.adding(days: -$0, to: today) }
        var candidates: [Candidate] = []

        // Shorter-than-usual night → resting heart rate that day.
        let sleepPairs = window.compactMap { day -> (sleep: Double, outcome: Double)? in
            guard let sleep = metrics.value(.sleepDuration, on: day),
                let outcome = metrics.value(.restingHeartRate, on: day)
            else { return nil }
            return (sleep, outcome)
        }
        if let medianSleep = Statistics.median(sleepPairs.map(\.sleep)) {
            candidates += candidate(
                id: "pattern.shorterSleep.restingHeartRate",
                condition: .shorterSleep,
                threshold: medianSleep,
                outcome: .restingHeartRate,
                with: sleepPairs.filter { $0.sleep < medianSleep }.map(\.outcome),
                without: sleepPairs.filter { $0.sleep >= medianSleep }.map(\.outcome)
            )
        }

        // Workout day → sleep that night (the night ending the next morning).
        if metrics.hasWorkoutData {
            var with: [Double] = []
            var without: [Double] = []
            for day in window {
                let nextDay = calendar.adding(days: 1, to: day)
                guard nextDay < today, let sleep = metrics.value(.sleepDuration, on: nextDay) else { continue }
                let minutes = metrics.value(.workoutMinutes, on: day) ?? 0
                if minutes >= PatternRules.workoutDayMinutes {
                    with.append(sleep)
                } else if minutes == 0 {
                    without.append(sleep)
                }
            }
            candidates += candidate(
                id: "pattern.workoutDay.sleepDuration",
                condition: .workoutDay,
                threshold: PatternRules.workoutDayMinutes,
                outcome: .sleepDuration,
                with: with,
                without: without
            )
        }

        let adjusted = Statistics.benjaminiHochberg(candidates.map(\.pValue))
        return zip(candidates, adjusted).compactMap { candidate, adjustedP in
            finding(for: candidate, adjustedPValue: adjustedP)
        }
        .sorted { lhs, rhs in
            guard case .groupDifference(let l) = lhs.detail, case .groupDifference(let r) = rhs.detail else {
                return lhs.id < rhs.id
            }
            return l.confidence != r.confidence ? l.confidence > r.confidence : lhs.id < rhs.id
        }
    }

    /// Returns a candidate only when both groups meet the size gates.
    private static func candidate(
        id: String,
        condition: Condition,
        threshold: Double,
        outcome: Metric,
        with: [Double],
        without: [Double]
    ) -> [Candidate] {
        guard with.count >= PatternRules.minimumDaysPerGroup,
            without.count >= PatternRules.minimumDaysPerGroup,
            with.count + without.count >= PatternRules.minimumPairedDays
        else { return [] }
        let pValue = Statistics.mannWhitneyPValue(with, without)
        return [
            Candidate(
                id: id,
                condition: condition,
                threshold: threshold,
                outcome: outcome,
                with: with,
                without: without,
                pValue: pValue
            )
        ]
    }

    private static func finding(for candidate: Candidate, adjustedPValue: Double) -> Finding? {
        guard adjustedPValue <= PatternRules.falseDiscoveryRate else { return nil }
        let withMedian = Statistics.median(candidate.with)!
        let withoutMedian = Statistics.median(candidate.without)!
        guard abs(withMedian - withoutMedian) >= PatternRules.minimumEffect(candidate.outcome) else { return nil }
        let interval = Statistics.bootstrapDifferenceInterval(
            candidate.with,
            candidate.without,
            resamples: PatternRules.resamples,
            seed: PatternRules.seed
        )
        // The interval must exclude zero.
        guard interval.lowerBound > 0 || interval.upperBound < 0 else { return nil }

        let smallerGroup = min(candidate.with.count, candidate.without.count)
        let confidence: Confidence =
            if smallerGroup >= 20 && adjustedPValue <= 0.01 {
                .high
            } else if smallerGroup >= 10 && adjustedPValue <= 0.05 {
                .medium
            } else {
                .low
            }

        let difference = GroupDifference(
            condition: candidate.condition,
            conditionThreshold: candidate.threshold,
            outcome: candidate.outcome,
            withConditionMedian: withMedian,
            withoutConditionMedian: withoutMedian,
            withConditionDays: candidate.with.count,
            withoutConditionDays: candidate.without.count,
            differenceLow: interval.lowerBound,
            differenceHigh: interval.upperBound,
            pValue: candidate.pValue,
            adjustedPValue: adjustedPValue,
            confidence: confidence
        )
        return Finding(id: candidate.id, detail: .groupDifference(difference))
    }
}
