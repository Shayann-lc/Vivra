import Foundation
import VivraModel

public enum Confidence: String, Codable, Sendable, Comparable {
    case low
    case medium
    case high

    private var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }

    public static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rank < rhs.rank }
}

/// A metric over the last 7 complete days, next to the 7 days before.
public struct WeeklyAverage: Codable, Sendable, Equatable {
    public let metric: Metric
    /// Mean of daily values, or the total for workout metrics.
    public let thisWeek: Double
    /// Days with data. Always 7 for workout totals.
    public let thisWeekDays: Int
    /// Nil when the previous week has too little data to compare.
    public let previousWeek: Double?
    public let previousWeekDays: Int

    public init(metric: Metric, thisWeek: Double, thisWeekDays: Int, previousWeek: Double?, previousWeekDays: Int) {
        self.metric = metric
        self.thisWeek = thisWeek
        self.thisWeekDays = thisWeekDays
        self.previousWeek = previousWeek
        self.previousWeekDays = previousWeekDays
    }
}

/// The day-level condition a group difference compares.
public enum Condition: String, Codable, Sendable {
    /// The night before was shorter than the person's median night.
    case shorterSleep
    /// A day with at least `PatternRules.workoutDayMinutes` of workouts,
    /// compared with days with none.
    case workoutDay
}

/// "On days with the condition, the outcome's median was X; on days
/// without it, Y." An association, never a cause.
public struct GroupDifference: Codable, Sendable, Equatable {
    public let condition: Condition
    /// The split point: median sleep in seconds, or minimum workout minutes.
    public let conditionThreshold: Double
    public let outcome: Metric
    public let withConditionMedian: Double
    public let withoutConditionMedian: Double
    public let withConditionDays: Int
    public let withoutConditionDays: Int
    /// 95% bootstrap interval for (with − without).
    public let differenceLow: Double
    public let differenceHigh: Double
    public let pValue: Double
    /// Benjamini–Hochberg adjusted across the patterns tested in the report.
    public let adjustedPValue: Double
    public let confidence: Confidence

    public init(
        condition: Condition,
        conditionThreshold: Double,
        outcome: Metric,
        withConditionMedian: Double,
        withoutConditionMedian: Double,
        withConditionDays: Int,
        withoutConditionDays: Int,
        differenceLow: Double,
        differenceHigh: Double,
        pValue: Double,
        adjustedPValue: Double,
        confidence: Confidence
    ) {
        self.condition = condition
        self.conditionThreshold = conditionThreshold
        self.outcome = outcome
        self.withConditionMedian = withConditionMedian
        self.withoutConditionMedian = withoutConditionMedian
        self.withConditionDays = withConditionDays
        self.withoutConditionDays = withoutConditionDays
        self.differenceLow = differenceLow
        self.differenceHigh = differenceHigh
        self.pValue = pValue
        self.adjustedPValue = adjustedPValue
        self.confidence = confidence
    }

    public var difference: Double { withConditionMedian - withoutConditionMedian }
}

/// A rank correlation between X on day t and Y on day t + lag, shown
/// concretely as Y's median in X's low and high groups.
public struct Correlation: Codable, Sendable, Equatable {
    public enum Split: String, Codable, Sendable {
        /// Bottom third of X against top third.
        case thirds
        /// Days with none of X against days with some (X is often zero).
        case noneVersusSome
    }

    public let x: Metric
    public let y: Metric
    /// 0: same day. 1: Y is the next day (for sleep, the following night).
    public let lag: Int
    public let rho: Double
    public let rhoLow: Double
    public let rhoHigh: Double
    /// Paired days.
    public let days: Int
    public let pValue: Double
    public let adjustedPValue: Double
    public let confidence: Confidence
    public let split: Split
    /// Largest X in the low group (0 for `noneVersusSome`).
    public let lowGroupMaxX: Double
    /// Smallest X in the high group.
    public let highGroupMinX: Double
    public let lowGroupMedianY: Double
    public let highGroupMedianY: Double
    public let lowGroupDays: Int
    public let highGroupDays: Int

    public init(
        x: Metric,
        y: Metric,
        lag: Int,
        rho: Double,
        rhoLow: Double,
        rhoHigh: Double,
        days: Int,
        pValue: Double,
        adjustedPValue: Double,
        confidence: Confidence,
        split: Split,
        lowGroupMaxX: Double,
        highGroupMinX: Double,
        lowGroupMedianY: Double,
        highGroupMedianY: Double,
        lowGroupDays: Int,
        highGroupDays: Int
    ) {
        self.x = x
        self.y = y
        self.lag = lag
        self.rho = rho
        self.rhoLow = rhoLow
        self.rhoHigh = rhoHigh
        self.days = days
        self.pValue = pValue
        self.adjustedPValue = adjustedPValue
        self.confidence = confidence
        self.split = split
        self.lowGroupMaxX = lowGroupMaxX
        self.highGroupMinX = highGroupMinX
        self.lowGroupMedianY = lowGroupMedianY
        self.highGroupMedianY = highGroupMedianY
        self.lowGroupDays = lowGroupDays
        self.highGroupDays = highGroupDays
    }
}

/// A steady change over the last `windowDays`, from the Theil–Sen line.
public struct Trend: Codable, Sendable, Equatable {
    public let metric: Metric
    public let windowDays: Int
    /// The line's value at the start and end of the window.
    public let startValue: Double
    public let endValue: Double
    /// Days with data in the window.
    public let days: Int
    public let pValue: Double
    public let adjustedPValue: Double
    public let confidence: Confidence

    public init(
        metric: Metric,
        windowDays: Int,
        startValue: Double,
        endValue: Double,
        days: Int,
        pValue: Double,
        adjustedPValue: Double,
        confidence: Confidence
    ) {
        self.metric = metric
        self.windowDays = windowDays
        self.startValue = startValue
        self.endValue = endValue
        self.days = days
        self.pValue = pValue
        self.adjustedPValue = adjustedPValue
        self.confidence = confidence
    }
}

/// A recent value well outside the person's own usual range.
public struct Anomaly: Codable, Sendable, Equatable {
    public let metric: Metric
    /// 0 today, 1 yesterday.
    public let daysAgo: Int
    public let value: Double
    /// 10th and 90th percentiles of the baseline.
    public let usualLow: Double
    public let usualHigh: Double
    public let baselineDays: Int

    public init(metric: Metric, daysAgo: Int, value: Double, usualLow: Double, usualHigh: Double, baselineDays: Int) {
        self.metric = metric
        self.daysAgo = daysAgo
        self.value = value
        self.usualLow = usualLow
        self.usualHigh = usualHigh
        self.baselineDays = baselineDays
    }

    public var isAbove: Bool { value > usualHigh }
}

/// A recent value next to the person's median, for the daily check-in.
public struct DayComparison: Codable, Sendable, Equatable {
    public let metric: Metric
    /// 0 today, 1 yesterday.
    public let daysAgo: Int
    public let value: Double
    public let baselineMedian: Double
    public let baselineDays: Int

    public init(metric: Metric, daysAgo: Int, value: Double, baselineMedian: Double, baselineDays: Int) {
        self.metric = metric
        self.daysAgo = daysAgo
        self.value = value
        self.baselineMedian = baselineMedian
        self.baselineDays = baselineDays
    }
}

/// A metric averaged over a period (30 days in the monthly report), next to
/// the period before.
public struct PeriodAverage: Codable, Sendable, Equatable {
    public let metric: Metric
    public let periodDays: Int
    /// Mean of daily values, or the total for workout metrics.
    public let value: Double
    public let valueDays: Int
    public let previous: Double?
    public let previousDays: Int

    public init(metric: Metric, periodDays: Int, value: Double, valueDays: Int, previous: Double?, previousDays: Int) {
        self.metric = metric
        self.periodDays = periodDays
        self.value = value
        self.valueDays = valueDays
        self.previous = previous
        self.previousDays = previousDays
    }
}

/// A known pattern whose condition was met recently: "yesterday you had
/// 190 mg of caffeine; on days with that much, you slept …". Used by the
/// feeling-off report. It describes a past association, never a reason.
public struct ApplicablePattern: Codable, Sendable, Equatable {
    public enum Basis: Codable, Sendable, Equatable {
        case correlation(Correlation)
        case groupDifference(GroupDifference)
    }

    public let basis: Basis
    /// The metric whose recent value matched the pattern.
    public let metric: Metric
    /// 0: today (or last night, for sleep). 1: yesterday.
    public let daysAgo: Int
    public let value: Double

    public init(basis: Basis, metric: Metric, daysAgo: Int, value: Double) {
        self.basis = basis
        self.metric = metric
        self.daysAgo = daysAgo
        self.value = value
    }

    public var confidence: Confidence {
        switch basis {
        case .correlation(let correlation): correlation.confidence
        case .groupDifference(let difference): difference.confidence
        }
    }
}

public enum FindingDetail: Codable, Sendable, Equatable {
    case weeklyAverage(WeeklyAverage)
    case groupDifference(GroupDifference)
    case correlation(Correlation)
    case trend(Trend)
    case anomaly(Anomaly)
    case dayComparison(DayComparison)
    case periodAverage(PeriodAverage)
    case applicablePattern(ApplicablePattern)

    /// Patterns and trends carry a confidence; descriptive findings don't.
    public var confidence: Confidence? {
        switch self {
        case .groupDifference(let difference): difference.confidence
        case .correlation(let correlation): correlation.confidence
        case .trend(let trend): trend.confidence
        case .applicablePattern(let pattern): pattern.confidence
        case .weeklyAverage, .anomaly, .dayComparison, .periodAverage: nil
        }
    }

    public var isPattern: Bool {
        switch self {
        case .groupDifference, .correlation: true
        default: false
        }
    }
}

/// A computed result. Structured numbers only, never prose: wording is the
/// narrative layer's job, and it may only restate these numbers.
public struct Finding: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let detail: FindingDetail
    /// The value is outside a bundled typical range. The UI suggests talking
    /// to a professional if the person has questions, and says nothing about
    /// what the value means.
    public let suggestProfessional: Bool

    public init(id: String, detail: FindingDetail, suggestProfessional: Bool = false) {
        self.id = id
        self.detail = detail
        self.suggestProfessional = suggestProfessional
    }
}

public enum ReportKind: String, Codable, Sendable, CaseIterable {
    case daily
    case weekly
    case monthly
    /// "Why do I feel off today?"
    case feelingOff
}

public struct InsightReport: Codable, Sendable, Equatable {
    public let kind: ReportKind
    /// The days covered (the same day for a daily check-in).
    public let periodStart: Day
    public let periodEnd: Day
    /// In priority order.
    public let findings: [Finding]

    public init(kind: ReportKind, periodStart: Day, periodEnd: Day, findings: [Finding]) {
        self.kind = kind
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.findings = findings
    }
}
