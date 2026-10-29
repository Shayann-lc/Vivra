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

/// One check the pattern finder made, with its finding or the reason it
/// didn't produce one. Connections shows every check; reports only use the
/// findings.
struct PatternCheck: Sendable, Equatable {
    let id: String
    let behaviour: ConnectionBehaviour
    let outcome: Metric
    /// Days from the behaviour's day to the outcome's day.
    let lag: Int
    let status: ConnectionStatus
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

    /// A check before the correction: either a candidate for it, or already
    /// dropped by a gate.
    private struct Draft {
        enum State {
            case candidate(Candidate)
            case dropped(ConnectionStatus)
        }

        let id: String
        let behaviour: ConnectionBehaviour
        let outcome: Metric
        let lag: Int
        let state: State
    }

    static func findings(metrics: DailyMetrics, today: Day, calendar: DayCalendar) -> [Finding] {
        checks(metrics: metrics, today: today, calendar: calendar)
            .compactMap { check in
                if case .found(let finding) = check.status { return finding }
                return nil
            }
            .sorted(by: byConfidence)
    }

    /// Every check in a fixed order: the two group differences, then the
    /// catalogue's correlations.
    static func checks(metrics: DailyMetrics, today: Day, calendar: DayCalendar) -> [PatternCheck] {
        let window = window(today: today, calendar: calendar)
        let drafts =
            groupDrafts(metrics: metrics, window: window, today: today, calendar: calendar)
            + correlationDrafts(metrics: metrics, window: window, today: today, calendar: calendar)

        var candidates: [Candidate] = []
        for draft in drafts {
            if case .candidate(let candidate) = draft.state { candidates.append(candidate) }
        }
        let adjusted = Statistics.benjaminiHochberg(candidates.map(\.pValue))
        let adjustedByID = Dictionary(uniqueKeysWithValues: zip(candidates.map(\.id), adjusted))

        return drafts.map { draft in
            let status: ConnectionStatus
            switch draft.state {
            case .dropped(let reason):
                status = reason
            case .candidate(let candidate):
                status = evaluate(candidate, adjustedPValue: adjustedByID[candidate.id]!)
            }
            return PatternCheck(
                id: draft.id, behaviour: draft.behaviour, outcome: draft.outcome, lag: draft.lag, status: status)
        }
    }

    /// Complete days only, oldest first.
    static func window(today: Day, calendar: DayCalendar) -> [Day] {
        (1...PatternRules.patternWindowDays).reversed().map { calendar.adding(days: -$0, to: today) }
    }

    private static func evaluate(_ candidate: Candidate, adjustedPValue: Double) -> ConnectionStatus {
        switch candidate.kind {
        case .group(let condition, let threshold, let outcome, let with, let without):
            guard adjustedPValue <= PatternRules.falseDiscoveryRate else {
                return .noClearPattern(days: with.count + without.count)
            }
            return groupStatus(
                id: candidate.id,
                condition: condition,
                threshold: threshold,
                outcome: outcome,
                with: with,
                without: without,
                pValue: candidate.pValue,
                adjustedPValue: adjustedPValue
            )
        case .correlation(let pair, let pairs, let rho):
            guard adjustedPValue <= PatternRules.falseDiscoveryRate else { return .noClearPattern(days: pairs.count) }
            return correlationStatus(
                pair: pair, pairs: pairs, rho: rho, pValue: candidate.pValue, adjustedPValue: adjustedPValue)
        }
    }

    static func byConfidence(_ lhs: Finding, _ rhs: Finding) -> Bool {
        let l = lhs.detail.confidence ?? .low
        let r = rhs.detail.confidence ?? .low
        return l != r ? l > r : lhs.id < rhs.id
    }

    /// Whether the metric has a value on any of the days.
    private static func isRecorded(_ metric: Metric, on days: [Day], metrics: DailyMetrics) -> Bool {
        days.contains { metrics.value(metric, on: $0) != nil }
    }

    // MARK: Group differences

    static let shorterSleepID = "pattern.shorterSleep.restingHeartRate"
    static let workoutDayID = "pattern.workoutDay.sleepDuration"

    /// Each night's sleep with the resting heart rate the same day.
    static func shorterSleepDays(metrics: DailyMetrics, window: [Day]) -> [(day: Day, sleep: Double, outcome: Double)] {
        window.compactMap { day in
            guard let sleep = metrics.value(.sleepDuration, on: day),
                let outcome = metrics.value(.restingHeartRate, on: day)
            else { return nil }
            return (day, sleep, outcome)
        }
    }

    /// Each day's workout minutes with the sleep the night after, while that
    /// night is complete.
    static func workoutDays(metrics: DailyMetrics, window: [Day], today: Day, calendar: DayCalendar) -> [(
        day: Day, minutes: Double, sleep: Double
    )] {
        window.compactMap { day in
            let nextDay = calendar.adding(days: 1, to: day)
            guard nextDay < today, let sleep = metrics.value(.sleepDuration, on: nextDay) else { return nil }
            return (day, metrics.value(.workoutMinutes, on: day) ?? 0, sleep)
        }
    }

    private static func groupDrafts(metrics: DailyMetrics, window: [Day], today: Day, calendar: DayCalendar)
        -> [Draft]
    {
        var drafts: [Draft] = []

        // Shorter-than-usual night → resting heart rate that day.
        let sleepPairs = shorterSleepDays(metrics: metrics, window: window)
        let shorterSleep = { (state: Draft.State) in
            Draft(
                id: shorterSleepID, behaviour: .condition(.shorterSleep), outcome: .restingHeartRate, lag: 0,
                state: state)
        }
        if let medianSleep = Statistics.median(sleepPairs.map(\.sleep)) {
            drafts.append(
                shorterSleep(
                    groupState(
                        id: shorterSleepID,
                        condition: .shorterSleep,
                        threshold: medianSleep,
                        outcome: .restingHeartRate,
                        with: sleepPairs.filter { $0.sleep < medianSleep }.map(\.outcome),
                        without: sleepPairs.filter { $0.sleep >= medianSleep }.map(\.outcome)
                    )))
        } else if !isRecorded(.sleepDuration, on: window, metrics: metrics) {
            drafts.append(shorterSleep(.dropped(.notRecorded(.sleepDuration))))
        } else if !isRecorded(.restingHeartRate, on: window, metrics: metrics) {
            drafts.append(shorterSleep(.dropped(.notRecorded(.restingHeartRate))))
        } else {
            drafts.append(shorterSleep(.dropped(.needsMoreDays(have: 0, need: PatternRules.minimumPairedDays))))
        }

        // Workout day → sleep that night (the night ending the next morning).
        let workoutDay = { (state: Draft.State) in
            Draft(id: workoutDayID, behaviour: .condition(.workoutDay), outcome: .sleepDuration, lag: 1, state: state)
        }
        if metrics.hasData(.workoutMinutes) {
            var with: [Double] = []
            var without: [Double] = []
            for entry in workoutDays(metrics: metrics, window: window, today: today, calendar: calendar) {
                if entry.minutes >= PatternRules.workoutDayMinutes {
                    with.append(entry.sleep)
                } else if entry.minutes == 0 {
                    without.append(entry.sleep)
                }
            }
            if with.isEmpty && without.isEmpty && !isRecorded(.sleepDuration, on: window, metrics: metrics) {
                drafts.append(workoutDay(.dropped(.notRecorded(.sleepDuration))))
            } else {
                drafts.append(
                    workoutDay(
                        groupState(
                            id: workoutDayID,
                            condition: .workoutDay,
                            threshold: PatternRules.workoutDayMinutes,
                            outcome: .sleepDuration,
                            with: with,
                            without: without
                        )))
            }
        } else {
            drafts.append(workoutDay(.dropped(.notRecorded(.workoutMinutes))))
        }
        return drafts
    }

    private static func groupState(
        id: String,
        condition: Condition,
        threshold: Double,
        outcome: Metric,
        with: [Double],
        without: [Double]
    ) -> Draft.State {
        let total = with.count + without.count
        guard total >= PatternRules.minimumPairedDays else {
            return .dropped(.needsMoreDays(have: total, need: PatternRules.minimumPairedDays))
        }
        guard with.count >= PatternRules.minimumDaysPerGroup, without.count >= PatternRules.minimumDaysPerGroup else {
            return .dropped(.notEnoughVariety(days: total))
        }
        return .candidate(
            Candidate(
                id: id,
                kind: .group(
                    condition: condition, threshold: threshold, outcome: outcome, with: with, without: without),
                pValue: Statistics.mannWhitneyPValue(with, without)
            ))
    }

    private static func groupStatus(
        id: String,
        condition: Condition,
        threshold: Double,
        outcome: Metric,
        with: [Double],
        without: [Double],
        pValue: Double,
        adjustedPValue: Double
    ) -> ConnectionStatus {
        let days = with.count + without.count
        let withMedian = Statistics.median(with)!
        let withoutMedian = Statistics.median(without)!
        guard abs(withMedian - withoutMedian) >= outcome.minimumEffect else { return .noClearPattern(days: days) }
        let interval = Statistics.bootstrapDifferenceInterval(
            with,
            without,
            resamples: PatternRules.resamples,
            seed: PatternRules.seed
        )
        guard interval.lowerBound > 0 || interval.upperBound < 0 else { return .noClearPattern(days: days) }

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
        return .found(Finding(id: id, detail: .groupDifference(difference)))
    }

    // MARK: Correlations

    /// X on each window day with Y on the day `lag` later, while that day is
    /// complete.
    static func correlationDays(
        _ pair: PatternCatalog.Pair,
        metrics: DailyMetrics,
        window: [Day],
        today: Day,
        calendar: DayCalendar
    ) -> [(day: Day, x: Double, y: Double)] {
        window.compactMap { day in
            let outcomeDay = calendar.adding(days: pair.lag, to: day)
            guard outcomeDay < today,
                let x = metrics.value(pair.x, on: day),
                let y = metrics.value(pair.y, on: outcomeDay)
            else { return nil }
            return (day, x, y)
        }
    }

    private static func correlationDrafts(
        metrics: DailyMetrics,
        window: [Day],
        today: Day,
        calendar: DayCalendar
    ) -> [Draft] {
        PatternCatalog.correlations.map { pair in
            let draft = { (state: Draft.State) in
                Draft(id: pair.id, behaviour: .metric(pair.x), outcome: pair.y, lag: pair.lag, state: state)
            }
            let pairs = correlationDays(pair, metrics: metrics, window: window, today: today, calendar: calendar)
                .map { (x: $0.x, y: $0.y) }
            guard pairs.count >= PatternRules.minimumPairedDays else {
                if !isRecorded(pair.x, on: window, metrics: metrics) {
                    return draft(.dropped(.notRecorded(pair.x)))
                }
                let outcomeDays = window.map { calendar.adding(days: pair.lag, to: $0) }.filter { $0 < today }
                if !isRecorded(pair.y, on: outcomeDays, metrics: metrics) {
                    return draft(.dropped(.notRecorded(pair.y)))
                }
                return draft(.dropped(.needsMoreDays(have: pairs.count, need: PatternRules.minimumPairedDays)))
            }
            guard let rho = Statistics.spearman(pairs.map(\.x), pairs.map(\.y)) else {
                return draft(.dropped(.notEnoughVariety(days: pairs.count)))
            }
            guard abs(rho) >= PatternRules.minimumRho else {
                return draft(.dropped(.noClearPattern(days: pairs.count)))
            }
            let inference = Statistics.spearmanInference(rho: rho, n: pairs.count)
            return draft(
                .candidate(
                    Candidate(
                        id: pair.id, kind: .correlation(pair, pairs: pairs, rho: rho), pValue: inference.pValue)))
        }
    }

    private static func correlationStatus(
        pair: PatternCatalog.Pair,
        pairs: [(x: Double, y: Double)],
        rho: Double,
        pValue: Double,
        adjustedPValue: Double
    ) -> ConnectionStatus {
        let interval = Statistics.spearmanInference(rho: rho, n: pairs.count).interval
        guard interval.lowerBound > 0 || interval.upperBound < 0 else { return .noClearPattern(days: pairs.count) }
        guard let groups = concreteGroups(pairs) else { return .notEnoughVariety(days: pairs.count) }
        let lowMedian = Statistics.median(groups.low.map(\.y))!
        let highMedian = Statistics.median(groups.high.map(\.y))!
        guard abs(highMedian - lowMedian) >= pair.y.minimumEffect else { return .noClearPattern(days: pairs.count) }

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
        return .found(Finding(id: pair.id, detail: .correlation(correlation)))
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
