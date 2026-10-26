import Foundation
import InsightEngine

/// Writes a summary without a language model. Deterministic, and always
/// passes `NarrativeValidator` (tested), so it is the safe fallback.
public enum TemplateRenderer {
    public static let headline = "Your last 7 days"
    public static let emptyHeadline = "Not enough data for a summary yet"

    public static func render(_ findings: [Finding]) -> NarrativeDraft {
        guard !findings.isEmpty else { return NarrativeDraft(headline: emptyHeadline, bullets: []) }
        return NarrativeDraft(
            headline: headline,
            bullets: findings.map { .init(findingID: $0.id, text: sentence(for: $0)) }
        )
    }

    public static func sentence(for finding: Finding) -> String {
        switch finding.detail {
        case .weeklyAverage(let average): sentence(for: average)
        case .groupDifference(let difference): sentence(for: difference)
        }
    }

    private static func sentence(for average: WeeklyAverage) -> String {
        let current = FindingFormatter.format(average.thisWeek, average.metric.unit)
        let previous = average.previousWeek.map { FindingFormatter.format($0, average.metric.unit) }
        let days = average.thisWeekDays

        switch average.metric {
        case .sleepDuration:
            return
                "You slept an average of \(current) a night over the last 7 days (\(days) \(plural(days, "night")) recorded)."
                + (previous.map { " The week before, the average was \($0)." } ?? "")
        case .restingHeartRate, .heartRateVariability, .walkingHeartRateAverage, .vo2Max:
            return
                "\(subject(average.metric)) averaged \(current) over the last 7 days (\(days) \(plural(days, "day")) recorded)."
                + (previous.map { " The week before, it averaged \($0)." } ?? "")
        case .workoutCount:
            let count = FindingFormatter.rounded(average.thisWeek)
            return "You recorded \(current) \(plural(count, "workout")) over the last 7 days"
                + (previous.map { ", compared with \($0) the week before." } ?? ".")
        case .workoutMinutes:
            return "Your workouts added up to \(current) over the last 7 days"
                + (previous.map { ", compared with \($0) the week before." } ?? ".")
        }
    }

    private static func sentence(for difference: GroupDifference) -> String {
        let with = FindingFormatter.format(difference.withConditionMedian, difference.outcome.unit)
        let without = FindingFormatter.format(difference.withoutConditionMedian, difference.outcome.unit)
        let counts = "\(difference.withConditionDays) and \(difference.withoutConditionDays)"
        let confidence = "\(difference.confidence.rawValue) confidence"

        switch difference.condition {
        case .shorterSleep:
            let threshold = FindingFormatter.duration(difference.conditionThreshold)
            return "On days after a night shorter than your median of \(threshold), "
                + "\(subject(difference.outcome).lowercasedFirst) had a median of \(with), "
                + "compared with \(without) after longer nights (\(counts) days compared, \(confidence))."
        case .workoutDay:
            let minutes = FindingFormatter.rounded(difference.conditionThreshold)
            return "On nights after a day with at least \(minutes) minutes of workouts, "
                + "\(outcomeClause(difference.outcome)) a median of \(with), "
                + "compared with \(without) after days without a workout (\(counts) nights compared, \(confidence))."
        }
    }

    private static func subject(_ metric: Metric) -> String {
        switch metric {
        case .restingHeartRate: "Your resting heart rate"
        case .heartRateVariability: "Your heart rate variability (SDNN)"
        case .walkingHeartRateAverage: "Your walking heart rate"
        case .vo2Max: "Your VO2 max estimate"
        case .sleepDuration: "Your sleep"
        case .workoutMinutes: "Your workout time"
        case .workoutCount: "Your workout count"
        }
    }

    private static func outcomeClause(_ metric: Metric) -> String {
        metric == .sleepDuration ? "you slept" : "\(subject(metric).lowercasedFirst) had"
    }

    private static func plural(_ count: Int, _ noun: String) -> String {
        count == 1 ? noun : noun + "s"
    }
}

extension String {
    fileprivate var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
