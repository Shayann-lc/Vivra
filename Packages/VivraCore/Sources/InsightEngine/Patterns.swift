import Foundation
import VivraModel

/// Thresholds for showing anything. Kept together so they're easy to review.
public enum PatternRules {
    /// A weekly average needs this many days with data.
    public static let minimumDaysPerWeek = 3
    /// Each side of a group difference needs this many days...
    public static let minimumDaysPerGroup = 7
    /// ...and both sides together, or a correlation, this many.
    public static let minimumPairedDays = 14
    /// Correlations weaker than this aren't reported.
    public static let minimumRho = 0.3
    /// Each group in a correlation's concrete comparison needs this many days.
    public static let minimumDaysPerThird = 5
    /// Benjamini–Hochberg false discovery rate.
    public static let falseDiscoveryRate = 0.10
    /// Days of history patterns look at.
    public static let patternWindowDays = 90
    /// A "workout day" has at least this many workout minutes.
    public static let workoutDayMinutes = 20.0
    public static let resamples = 2_000
    public static let seed: UInt64 = 0x5EED_0F_71F4
}

/// The correlations the engine tests: directional, plausible pairs only, so
/// multiple testing stays small and every pattern is meaningful. X is
/// measured on day t and Y on day t + lag.
public enum PatternCatalog {
    public struct Pair: Sendable, Equatable {
        public let x: Metric
        public let y: Metric
        public let lag: Int

        public var id: String { "pattern.\(x.rawValue).\(y.rawValue).lag\(lag)" }
    }

    public static let correlations: [Pair] = [
        // Evening intake and the night or day after.
        Pair(x: .alcohol, y: .heartRateVariability, lag: 1),
        Pair(x: .alcohol, y: .restingHeartRate, lag: 1),
        Pair(x: .alcohol, y: .sleepDuration, lag: 1),
        Pair(x: .caffeine, y: .sleepDuration, lag: 1),
        // Activity and the night after.
        Pair(x: .steps, y: .sleepDuration, lag: 1),
        Pair(x: .exerciseMinutes, y: .heartRateVariability, lag: 1),
        // Mind.
        Pair(x: .mindfulMinutes, y: .stressLevel, lag: 0),
        Pair(x: .mindfulMinutes, y: .sleepDuration, lag: 1),
        Pair(x: .stressLevel, y: .sleepDuration, lag: 1),
        // Last night's sleep and the day that follows (sleep on day t is the
        // night ending that morning, so lag 0 means "the day after").
        Pair(x: .sleepDuration, y: .mood, lag: 0),
        Pair(x: .sleepDuration, y: .energyLevel, lag: 0),
        Pair(x: .sleepDuration, y: .stressLevel, lag: 0),
        Pair(x: .sleepDuration, y: .heartRateVariability, lag: 0),
        // Same-day activity and mood.
        Pair(x: .steps, y: .mood, lag: 0),
        Pair(x: .exerciseMinutes, y: .mood, lag: 0),
    ]
}

/// Finds group differences and correlations over the pattern window, with
/// one Benjamini–Hochberg correction across all of them.
enum PatternFinder {
    private enum Kind {
        case group(condition: Condition, threshold: Double, outcome: Metric, with: [Double], without: [Double])
        case correlation(PatternCatalog.Pair, pairs: [(x: Double, y: Double)], rho: Double)
    }

    private struct Candidate {
        let id: String
        let kind: Kind
        let pValue: Double
    }

    static func findings(metrics: DailyMetrics, today: Day, calendar: DayCalendar) -> [Finding] {
        // Complete days only, oldest first.
        let window = (1...PatternRules.patternWindowDays).reversed().map { calendar.adding(days: -$0, to: today) }
        var candidates = groupCandidates(metrics: metrics, window: window, today: today, calendar: calendar)
        candidates += correlationCandidates(metrics: metrics, window: window, today: today, calendar: calendar)

        let adjusted = Statistics.benjaminiHochberg(candidates.map(\.pValue))
        return zip(candidates, adjusted).compactMap { candidate, adjustedP in
            guard adjustedP <= PatternRules.falseDiscoveryRate else { return nil }
            switch candidate.kind {
            case .group(let condition, let threshold, let outcome, let with, let without):
                return groupFinding(
                    id: candidate.id,
                    condition: condition,
                    threshold: threshold,
                    outcome: outcome,
                    with: with,
                    without: without,
                    pValue: candidate.pValue,
                    adjustedPValue: adjustedP
                )
            case .correlation(let pair, let pairs, let rho):
                return correlationFinding(
                    pair: pair, pairs: pairs, rho: rho, pValue: candidate.pValue, adjustedPValue: adjustedP)
            }
        }
        .sorted(by: byConfidence)
    }

    static func byConfidence(_ lhs: Finding, _ rhs: Finding) -> Bool {
        let l = lhs.detail.confidence ?? .low
        let r = rhs.detail.confidence ?? .low
        return l != r ? l > r : lhs.id < rhs.id
    }

    // MARK: Group differences

    private static func groupCandidates(metrics: DailyMetrics, window: [Day], today: Day, calendar: DayCalendar)
        -> [Candidate]
    {
        var candidates: [Candidate] = []

        // Shorter-than-usual night → resting heart rate that day.
        let sleepPairs = window.compactMap { day -> (sleep: Double, outcome: Double)? in
            guard let sleep = metrics.value(.sleepDuration, on: day),
                let outcome = metrics.value(.restingHeartRate, on: day)
            else { return nil }
            return (sleep, outcome)
        }
        if let medianSleep = Statistics.median(sleepPairs.map(\.sleep)) {
            candidates += groupCandidate(
                id: "pattern.shorterSleep.restingHeartRate",
                condition: .shorterSleep,
                threshold: medianSleep,
                outcome: .restingHeartRate,
                with: sleepPairs.filter { $0.sleep < medianSleep }.map(\.outcome),
                without: sleepPairs.filter { $0.sleep >= medianSleep }.map(\.outcome)
            )
        }

        // Workout day → sleep that night (the night ending the next morning).
        if metrics.hasData(.workoutMinutes) {
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
            candidates += groupCandidate(
                id: "pattern.workoutDay.sleepDuration",
                condition: .workoutDay,
                threshold: PatternRules.workoutDayMinutes,
                outcome: .sleepDuration,
                with: with,
                without: without
            )
        }
        return candidates
    }

    private static func groupCandidate(
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
        return [
            Candidate(
                id: id,
                kind: .group(
                    condition: condition, threshold: threshold, outcome: outcome, with: with, without: without),
                pValue: Statistics.mannWhitneyPValue(with, without)
            )
        ]
    }

    private static func groupFinding(
        id: String,
        condition: Condition,
        threshold: Double,
        outcome: Metric,
        with: [Double],
        without: [Double],
        pValue: Double,
        adjustedPValue: Double
    ) -> Finding? {
        let withMedian = Statistics.median(with)!
        let withoutMedian = Statistics.median(without)!
        guard abs(withMedian - withoutMedian) >= outcome.minimumEffect else { return nil }
        let interval = Statistics.bootstrapDifferenceInterval(
            with,
            without,
            resamples: PatternRules.resamples,
            seed: PatternRules.seed
        )
        guard interval.lowerBound > 0 || interval.upperBound < 0 else { return nil }

        let smallerGroup = min(with.count, without.count)
        let confidence: Confidence =
            if smallerGroup >= 20 && adjustedPValue <= 0.01 {
                .high
            } else if smallerGroup >= 10 && adjustedPValue <= 0.05 {
                .medium
            } else {
                .low
            }
        let difference = GroupDifference(
            condition: condition,
            conditionThreshold: threshold,
            outcome: outcome,
            withConditionMedian: withMedian,
            withoutConditionMedian: withoutMedian,
            withConditionDays: with.count,
            withoutConditionDays: without.count,
            differenceLow: interval.lowerBound,
            differenceHigh: interval.upperBound,
            pValue: pValue,
            adjustedPValue: adjustedPValue,
            confidence: confidence
        )
        return Finding(id: id, detail: .groupDifference(difference))
    }

    // MARK: Correlations

    private static func correlationCandidates(
        metrics: DailyMetrics,
        window: [Day],
        today: Day,
        calendar: DayCalendar
    ) -> [Candidate] {
        PatternCatalog.correlations.compactMap { pair in
            let pairs = window.compactMap { day -> (x: Double, y: Double)? in
                let outcomeDay = calendar.adding(days: pair.lag, to: day)
                guard outcomeDay < today,
                    let x = metrics.value(pair.x, on: day),
                    let y = metrics.value(pair.y, on: outcomeDay)
                else { return nil }
                return (x, y)
            }
            guard pairs.count >= PatternRules.minimumPairedDays,
                let rho = Statistics.spearman(pairs.map(\.x), pairs.map(\.y)),
                abs(rho) >= PatternRules.minimumRho
            else { return nil }
            let inference = Statistics.spearmanInference(rho: rho, n: pairs.count)
            return Candidate(id: pair.id, kind: .correlation(pair, pairs: pairs, rho: rho), pValue: inference.pValue)
        }
    }

    private static func correlationFinding(
        pair: PatternCatalog.Pair,
        pairs: [(x: Double, y: Double)],
        rho: Double,
        pValue: Double,
        adjustedPValue: Double
    ) -> Finding? {
        let interval = Statistics.spearmanInference(rho: rho, n: pairs.count).interval
        guard interval.lowerBound > 0 || interval.upperBound < 0 else { return nil }
        guard let groups = concreteGroups(pairs) else { return nil }
        let lowMedian = Statistics.median(groups.low.map(\.y))!
        let highMedian = Statistics.median(groups.high.map(\.y))!
        guard abs(highMedian - lowMedian) >= pair.y.minimumEffect else { return nil }

        let stable = stability(pairs, rho: rho)
        let confidence: Confidence =
            if pairs.count >= 28 && adjustedPValue <= 0.01 && stable == true {
                .high
            } else if adjustedPValue <= 0.05 && stable != false {
                .medium
            } else {
                .low
            }
        let correlation = Correlation(
            x: pair.x,
            y: pair.y,
            lag: pair.lag,
            rho: rho,
            rhoLow: interval.lowerBound,
            rhoHigh: interval.upperBound,
            days: pairs.count,
            pValue: pValue,
            adjustedPValue: adjustedPValue,
            confidence: confidence,
            split: groups.split,
            lowGroupMaxX: groups.low.map(\.x).max()!,
            highGroupMinX: groups.high.map(\.x).min()!,
            lowGroupMedianY: lowMedian,
            highGroupMedianY: highMedian,
            lowGroupDays: groups.low.count,
            highGroupDays: groups.high.count
        )
        return Finding(id: pair.id, detail: .correlation(correlation))
    }

    /// Splits pairs into low and high X groups for a concrete comparison:
    /// "none vs some" when at least a third of X is tied at its minimum,
    /// otherwise bottom third against top third. Nil when a group is too
    /// small or the groups overlap.
    static func concreteGroups(_ pairs: [(x: Double, y: Double)]) -> (
        split: Correlation.Split, low: [(x: Double, y: Double)], high: [(x: Double, y: Double)]
    )? {
        let sorted = pairs.sorted { $0.x < $1.x }
        let minimum = sorted.first!.x
        let atMinimum = sorted.filter { $0.x == minimum }
        let split: Correlation.Split
        let low: [(x: Double, y: Double)]
        let high: [(x: Double, y: Double)]
        if atMinimum.count * 3 >= sorted.count {
            split = .noneVersusSome
            low = atMinimum
            high = sorted.filter { $0.x > minimum }
        } else {
            split = .thirds
            let third = (sorted.count + 2) / 3
            let lowCut = sorted[third - 1].x
            let highCut = sorted[sorted.count - third].x
            low = sorted.filter { $0.x <= lowCut }
            high = sorted.filter { $0.x >= highCut }
        }
        guard low.count >= PatternRules.minimumDaysPerThird, high.count >= PatternRules.minimumDaysPerThird,
            low.map(\.x).max()! < high.map(\.x).min()!
        else { return nil }
        return (split, low, high)
    }

    /// True when ρ has the same sign in both halves of the window (each with
    /// n ≥ 7), false when it doesn't, nil when a half is too small to tell.
    static func stability(_ pairs: [(x: Double, y: Double)], rho: Double) -> Bool? {
        let half = pairs.count / 2
        let halves = [Array(pairs[..<half]), Array(pairs[half...])]
        guard halves.allSatisfy({ $0.count >= 7 }) else { return nil }
        for part in halves {
            guard let partRho = Statistics.spearman(part.map(\.x), part.map(\.y)) else { return false }
            if partRho * rho <= 0 { return false }
        }
        return true
    }
}
