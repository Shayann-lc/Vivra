import Foundation
import VivraModel

/// What a connection compares on the behaviour side: a metric's own values
/// (a correlation) or a day-level condition (a group difference).
public enum ConnectionBehaviour: Sendable, Hashable {
    case metric(Metric)
    case condition(Condition)

    /// The metric the behaviour is measured with.
    public var metric: Metric {
        switch self {
        case .metric(let metric): metric
        case .condition(.shorterSleep): .sleepDuration
        case .condition(.workoutDay): .workoutMinutes
        }
    }
}

/// Where a check ended up. Only `found` carries numbers about the outcome;
/// the others say why there's nothing to show, so noise is never presented
/// as a near-finding.
public enum ConnectionStatus: Sendable, Equatable {
    /// Passed every gate. The finding is the one reports and Patterns use.
    case found(Finding)
    /// Tested on `days` paired days; not clear enough to show.
    case noClearPattern(days: Int)
    /// Enough days, but the behaviour barely varied, so there were no two
    /// groups to compare.
    case notEnoughVariety(days: Int)
    /// Fewer paired days than the test needs.
    case needsMoreDays(have: Int, need: Int)
    /// The metric has no data in the window.
    case notRecorded(Metric)

    public var finding: Finding? {
        if case .found(let finding) = self { return finding }
        return nil
    }
}

/// Which of a connection's two groups a day falls in. `less` is the day with
/// less or none of the behaviour; `more` is the day with more or some.
public enum ConnectionSide: String, Sendable, Equatable {
    case less
    case more
}

/// Every behaviour–outcome check Vivra makes, found or not, for the
/// Connections screen. Built from the same checks, gates and correction as
/// the patterns in reports, so a found row is exactly the reported pattern.
public struct ConnectionBoard: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable {
        /// The pattern's ID (`PatternCatalog.Pair.id` or the group's).
        public let id: String
        public let behaviour: ConnectionBehaviour
        public let outcome: Metric
        /// Days from the behaviour's day to the outcome's day.
        public let lag: Int
        public let status: ConnectionStatus
        /// The behaviour's most recent complete value and the group it falls
        /// in. Found rows only; nil when it falls between the groups.
        public let latest: Latest?
        /// The difference between the two groups relative to the outcome's
        /// usual range. For ordering only; never shown.
        public let sortKey: Double

        public var comparison: Comparison? { status.finding.flatMap(Comparison.init) }
    }

    public struct Latest: Sendable, Equatable {
        /// 0: today (last night, for sleep). 1: yesterday.
        public let daysAgo: Int
        public let value: Double
        public let side: ConnectionSide
    }

    /// The two groups of a found row, as less/none against more/some.
    public struct Comparison: Sendable, Equatable {
        public let lessMedian: Double
        public let lessDays: Int
        public let moreMedian: Double
        public let moreDays: Int
        public let confidence: Confidence

        init?(_ finding: Finding) {
            switch finding.detail {
            case .correlation(let correlation):
                lessMedian = correlation.lowGroupMedianY
                lessDays = correlation.lowGroupDays
                moreMedian = correlation.highGroupMedianY
                moreDays = correlation.highGroupDays
                confidence = correlation.confidence
            case .groupDifference(let difference):
                // Shorter nights are the "less" side of sleep; workout days
                // are the "more" side of workouts.
                let withIsMore = difference.condition == .workoutDay
                lessMedian = withIsMore ? difference.withoutConditionMedian : difference.withConditionMedian
                lessDays = withIsMore ? difference.withoutConditionDays : difference.withConditionDays
                moreMedian = withIsMore ? difference.withConditionMedian : difference.withoutConditionMedian
                moreDays = withIsMore ? difference.withConditionDays : difference.withoutConditionDays
                confidence = difference.confidence
            default:
                return nil
            }
        }
    }

    /// An outcome's values over the window.
    public struct Usual: Sendable, Equatable {
        public let median: Double
        /// 10th and 90th percentiles: the shaded usual range.
        public let low: Double
        public let high: Double
        /// 5th and 95th percentiles: the axis, so small differences look small.
        public let axisLow: Double
        public let axisHigh: Double
        public let days: Int
    }

    /// In a fixed order: outcomes as in `outcomeOrder`; within one, found
    /// rows by confidence then size of difference, then the rest.
    public let rows: [Row]
    /// For outcomes with at least `minimumUsualDays` days in the window.
    public let usual: [Metric: Usual]
    public let windowDays: Int

    public static let outcomeOrder: [Metric] = [
        .sleepDuration, .restingHeartRate, .heartRateVariability, .mood, .energyLevel, .stressLevel,
    ]
    /// The order of the "by habit" view.
    public static let behaviourOrder: [Metric] = [
        .sleepDuration, .alcohol, .caffeine, .steps, .exerciseMinutes, .workoutMinutes, .mindfulMinutes, .stressLevel,
    ]
    static let minimumUsualDays = 7

    public var found: [Row] { rows.filter { $0.status.finding != nil } }

    public func rows(outcome: Metric) -> [Row] { rows.filter { $0.outcome == outcome } }

    public func rows(behaviour metric: Metric) -> [Row] {
        rows.filter { $0.behaviour.metric == metric }
            .sorted { lhs, rhs in
                let l = Self.outcomeOrder.firstIndex(of: lhs.outcome) ?? .max
                let r = Self.outcomeOrder.firstIndex(of: rhs.outcome) ?? .max
                return l != r ? l < r : lhs.id < rhs.id
            }
    }

    public func row(id: String) -> Row? { rows.first { $0.id == id } }

    public static func build(
        _ dataset: HealthDataset,
        clock: any Clock,
        calendar: DayCalendar,
        sourcePolicy: SourcePolicy = .default
    ) -> ConnectionBoard {
        let metrics = DailyMetrics.build(dataset, calendar: calendar, sourcePolicy: sourcePolicy)
        let today = calendar.day(clock.now)
        let window = PatternFinder.window(today: today, calendar: calendar)

        var usual: [Metric: Usual] = [:]
        for outcome in outcomeOrder {
            let values = window.compactMap { metrics.value(outcome, on: $0) }.sorted()
            guard values.count >= minimumUsualDays else { continue }
            usual[outcome] = Usual(
                median: Statistics.median(values)!,
                low: Statistics.percentile(values, 0.1),
                high: Statistics.percentile(values, 0.9),
                axisLow: Statistics.percentile(values, 0.05),
                axisHigh: Statistics.percentile(values, 0.95),
                days: values.count
            )
        }

        let rows = PatternFinder.checks(metrics: metrics, today: today, calendar: calendar).map { check in
            Row(
                id: check.id,
                behaviour: check.behaviour,
                outcome: check.outcome,
                lag: check.lag,
                status: check.status,
                latest: check.status.finding.flatMap {
                    latest(for: $0, metrics: metrics, today: today, calendar: calendar)
                },
                sortKey: sortKey(check.status, usual: usual[check.outcome])
            )
        }
        return ConnectionBoard(rows: ordered(rows), usual: usual, windowDays: PatternRules.patternWindowDays)
    }

    static func sortKey(_ status: ConnectionStatus, usual: Usual?) -> Double {
        guard let comparison = status.finding.flatMap(Comparison.init) else { return 0 }
        let difference = abs(comparison.moreMedian - comparison.lessMedian)
        guard let usual, usual.high > usual.low else { return difference }
        return difference / (usual.high - usual.low)
    }

    private static func ordered(_ rows: [Row]) -> [Row] {
        func rank(_ status: ConnectionStatus) -> Int {
            switch status {
            case .found: 0
            case .noClearPattern: 1
            case .notEnoughVariety: 2
            case .needsMoreDays: 3
            case .notRecorded: 4
            }
        }
        return rows.sorted { lhs, rhs in
            let l = outcomeOrder.firstIndex(of: lhs.outcome) ?? .max
            let r = outcomeOrder.firstIndex(of: rhs.outcome) ?? .max
            if l != r { return l < r }
            if rank(lhs.status) != rank(rhs.status) { return rank(lhs.status) < rank(rhs.status) }
            let lc = lhs.comparison?.confidence ?? .low
            let rc = rhs.comparison?.confidence ?? .low
            if lc != rc { return lc > rc }
            if lhs.sortKey != rhs.sortKey { return lhs.sortKey > rhs.sortKey }
            return lhs.id < rhs.id
        }
    }

    /// The behaviour's most recent complete value, on the day whose outcome
    /// is the latest: today minus the lag. A daily total that's still adding
    /// up (steps today) isn't complete, so yesterday's is used instead.
    static func latest(for finding: Finding, metrics: DailyMetrics, today: Day, calendar: DayCalendar) -> Latest? {
        switch finding.detail {
        case .correlation(let correlation):
            let daysAgo = correlation.lag == 0 && correlation.x.addsUpThroughTheDay ? 1 : correlation.lag
            guard let value = metrics.value(correlation.x, on: calendar.adding(days: -daysAgo, to: today)) else {
                return nil
            }
            if value <= correlation.lowGroupMaxX { return Latest(daysAgo: daysAgo, value: value, side: .less) }
            if value >= correlation.highGroupMinX { return Latest(daysAgo: daysAgo, value: value, side: .more) }
            return nil
        case .groupDifference(let difference):
            switch difference.condition {
            case .shorterSleep:
                guard let sleep = metrics.value(.sleepDuration, on: today) else { return nil }
                return Latest(
                    daysAgo: 0, value: sleep, side: sleep < difference.conditionThreshold ? .less : .more)
            case .workoutDay:
                let minutes = metrics.value(.workoutMinutes, on: calendar.adding(days: -1, to: today)) ?? 0
                if minutes >= difference.conditionThreshold { return Latest(daysAgo: 1, value: minutes, side: .more) }
                if minutes == 0 { return Latest(daysAgo: 1, value: 0, side: .less) }
                return nil
            }
        default:
            return nil
        }
    }
}

/// The days behind one found connection: every paired day in the window with
/// its group, and the last 28 days of both metrics lined up by lag.
public struct ConnectionDays: Sendable, Equatable {
    public enum Group: String, Sendable, Equatable {
        case less
        /// Between the two groups; not part of the comparison.
        case between
        case more
    }

    public struct Pair: Sendable, Equatable, Identifiable {
        public let behaviourDay: Day
        public let outcomeDay: Day
        public let behaviour: Double
        public let outcome: Double
        public let group: Group
        public var id: Day { behaviourDay }
    }

    /// One behaviour day in the timeline, with the outcome `lag` days later
    /// shown on the same row.
    public struct TimelineDay: Sendable, Equatable, Identifiable {
        public let day: Day
        public let behaviour: Double?
        public let outcome: Double?
        public let group: Group?
        public var id: Day { day }
    }

    /// Oldest first.
    public let pairs: [Pair]
    /// The last `timelineDays` behaviour days of the window, oldest first.
    public let timeline: [TimelineDay]

    public static let timelineDays = 28

    public func pairs(in group: Group) -> [Pair] { pairs.filter { $0.group == group } }

    public static func build(
        _ finding: Finding,
        dataset: HealthDataset,
        clock: any Clock,
        calendar: DayCalendar,
        sourcePolicy: SourcePolicy = .default
    ) -> ConnectionDays? {
        let metrics = DailyMetrics.build(dataset, calendar: calendar, sourcePolicy: sourcePolicy)
        let today = calendar.day(clock.now)
        let window = PatternFinder.window(today: today, calendar: calendar)

        let pairs: [Pair]
        switch finding.detail {
        case .correlation(let correlation):
            let pair = PatternCatalog.Pair(x: correlation.x, y: correlation.y, lag: correlation.lag)
            pairs = PatternFinder.correlationDays(
                pair, metrics: metrics, window: window, today: today, calendar: calendar
            )
            .map { entry in
                let group: Group =
                    entry.x <= correlation.lowGroupMaxX
                    ? .less : entry.x >= correlation.highGroupMinX ? .more : .between
                return Pair(
                    behaviourDay: entry.day, outcomeDay: calendar.adding(days: correlation.lag, to: entry.day),
                    behaviour: entry.x, outcome: entry.y, group: group)
            }
        case .groupDifference(let difference):
            switch difference.condition {
            case .shorterSleep:
                pairs = PatternFinder.shorterSleepDays(metrics: metrics, window: window).map { entry in
                    Pair(
                        behaviourDay: entry.day, outcomeDay: entry.day, behaviour: entry.sleep, outcome: entry.outcome,
                        group: entry.sleep < difference.conditionThreshold ? .less : .more)
                }
            case .workoutDay:
                pairs = PatternFinder.workoutDays(metrics: metrics, window: window, today: today, calendar: calendar)
                    .map { entry in
                        let group: Group =
                            entry.minutes >= difference.conditionThreshold
                            ? .more : entry.minutes == 0 ? .less : .between
                        return Pair(
                            behaviourDay: entry.day, outcomeDay: calendar.adding(days: 1, to: entry.day),
                            behaviour: entry.minutes, outcome: entry.sleep, group: group)
                    }
            }
        default:
            return nil
        }

        let byDay = Dictionary(uniqueKeysWithValues: pairs.map { ($0.behaviourDay, $0) })
        let behaviour = ConnectionBehaviour.from(finding)
        let lag = Self.lag(finding)
        let timeline = window.suffix(timelineDays).map { day in
            if let pair = byDay[day] {
                return TimelineDay(day: day, behaviour: pair.behaviour, outcome: pair.outcome, group: pair.group)
            }
            let outcomeDay = calendar.adding(days: lag, to: day)
            return TimelineDay(
                day: day,
                behaviour: behaviour.flatMap { metrics.value($0.metric, on: day) },
                outcome: outcomeDay < today ? Self.outcome(finding).flatMap { metrics.value($0, on: outcomeDay) } : nil,
                group: nil
            )
        }
        return ConnectionDays(pairs: pairs, timeline: timeline)
    }

    private static func lag(_ finding: Finding) -> Int {
        switch finding.detail {
        case .correlation(let correlation): correlation.lag
        case .groupDifference(let difference): difference.condition == .workoutDay ? 1 : 0
        default: 0
        }
    }

    private static func outcome(_ finding: Finding) -> Metric? {
        switch finding.detail {
        case .correlation(let correlation): correlation.y
        case .groupDifference(let difference): difference.outcome
        default: nil
        }
    }
}

extension ConnectionBehaviour {
    static func from(_ finding: Finding) -> ConnectionBehaviour? {
        switch finding.detail {
        case .correlation(let correlation): .metric(correlation.x)
        case .groupDifference(let difference): .condition(difference.condition)
        default: nil
        }
    }
}
