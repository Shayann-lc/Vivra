import Foundation
import VivraModel

/// A metric the engine reports on, with its unit.
public enum Metric: String, Codable, Sendable, CaseIterable {
    /// Time asleep per night.
    case sleepDuration
    case restingHeartRate
    case heartRateVariability
    case walkingHeartRateAverage
    case vo2Max
    /// Total workout minutes over the period.
    case workoutMinutes
    /// Number of workouts over the period.
    case workoutCount

    public var unit: MetricUnit {
        switch self {
        case .sleepDuration: .seconds
        case .restingHeartRate, .walkingHeartRateAverage: .beatsPerMinute
        case .heartRateVariability: .milliseconds
        case .vo2Max: .millilitersPerKilogramMinute
        case .workoutMinutes: .minutes
        case .workoutCount: .count
        }
    }
}

public enum MetricUnit: String, Codable, Sendable {
    case seconds
    case beatsPerMinute
    case milliseconds
    case millilitersPerKilogramMinute
    case minutes
    case count
}

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

/// The day-level condition a pattern compares.
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

public enum FindingDetail: Codable, Sendable, Equatable {
    case weeklyAverage(WeeklyAverage)
    case groupDifference(GroupDifference)
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

public struct WeeklyReport: Codable, Sendable, Equatable {
    /// First and last day of the 7-day window (the last is yesterday).
    public let periodStart: Day
    public let periodEnd: Day
    public let findings: [Finding]

    public init(periodStart: Day, periodEnd: Day, findings: [Finding]) {
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.findings = findings
    }
}
