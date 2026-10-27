import Foundation
import InsightEngine

/// Writes a summary without a language model. Deterministic, and always
/// passes `NarrativeValidator` (tested), so it is the safe fallback.
public enum TemplateRenderer {
    public static func headline(for kind: ReportKind) -> String {
        switch kind {
        case .weekly: "Your last 7 days"
        case .daily: "Today's check-in"
        case .monthly: "Your last 30 days"
        case .feelingOff: "What stood out today"
        }
    }

    public static func emptyHeadline(for kind: ReportKind) -> String {
        switch kind {
        case .weekly: "Not enough data for a summary yet"
        case .daily: "Not enough data for a check-in yet"
        case .monthly: "Not enough data for a monthly summary yet"
        case .feelingOff: "Nothing stood out in today's data"
        }
    }

    public static func render(_ findings: [Finding], kind: ReportKind) -> NarrativeDraft {
        guard !findings.isEmpty else { return NarrativeDraft(headline: emptyHeadline(for: kind), bullets: []) }
        return NarrativeDraft(
            headline: headline(for: kind),
            bullets: findings.map { .init(findingID: $0.id, text: sentence(for: $0)) }
        )
    }

    public static func sentence(for finding: Finding) -> String {
        switch finding.detail {
        case .weeklyAverage(let average): sentence(for: average)
        case .groupDifference(let difference): sentence(for: difference)
        case .correlation(let correlation): sentence(for: correlation)
        case .trend(let trend): sentence(for: trend)
        case .anomaly(let anomaly): sentence(for: anomaly)
        case .dayComparison(let comparison): sentence(for: comparison)
        case .periodAverage(let average): sentence(for: average)
        case .applicablePattern(let pattern): sentence(for: pattern)
        }
    }

    // MARK: Period averages

    private static func sentence(for average: PeriodAverage) -> String {
        let metric = average.metric
        let current = format(average.value, metric)
        let previous = average.previous.map { format($0, metric) }
        let period = "the last \(average.periodDays) days"
        let before = "In the \(average.periodDays) days before"
        let days = average.valueDays

        switch metric {
        case .sleepDuration:
            return
                "You slept an average of \(current) a night over \(period) (\(days) \(plural(days, "night")) recorded)."
                + (previous.map { " \(before), the average was \($0)." } ?? "")
        case .workoutCount:
            let count = FindingFormatter.rounded(average.value)
            return "You recorded \(current) \(plural(count, "workout")) over \(period)"
                + (previous.map { ", compared with \($0) in the \(average.periodDays) days before." } ?? ".")
        case .workoutMinutes:
            return "Your workouts added up to \(current) over \(period)"
                + (previous.map { ", compared with \($0) in the \(average.periodDays) days before." } ?? ".")
        default:
            if MetricWords.isDailyTotal(metric) {
                return
                    "You averaged \(current)\(MetricWords.amountSuffix(metric)) a day over \(period) (\(days) \(plural(days, "day")) recorded)."
                    + (previous.map { " \(before), the average was \($0)." } ?? "")
            }
            return
                "Your \(MetricWords.noun(metric)) averaged \(current) over \(period) (\(days) \(plural(days, "day")) recorded)."
                + (previous.map { " \(before), it averaged \($0)." } ?? "")
        }
    }

    // MARK: Applicable patterns

    private static func sentence(for pattern: ApplicablePattern) -> String {
        let value = format(pattern.value, pattern.metric)
        let recent: String =
            if pattern.metric == .sleepDuration {
                "Last night you slept \(value)."
            } else if MetricWords.isDailyTotal(pattern.metric) {
                "\(MetricWords.when(pattern.daysAgo).capitalizedFirst) you recorded \(value)\(MetricWords.amountSuffix(pattern.metric))."
            } else {
                "\(MetricWords.when(pattern.daysAgo).capitalizedFirst) your \(MetricWords.noun(pattern.metric)) was \(value)."
            }
        let earlier: String =
            switch pattern.basis {
            case .correlation(let correlation): sentence(for: correlation)
            case .groupDifference(let difference): sentence(for: difference)
            }
        return "\(recent) In your recent history: \(earlier.lowercasedFirst)"
    }

    // MARK: Weekly averages

    private static func sentence(for average: WeeklyAverage) -> String {
        let metric = average.metric
        let current = format(average.thisWeek, metric)
        let previous = average.previousWeek.map { format($0, metric) }
        let days = average.thisWeekDays

        switch metric {
        case .sleepDuration:
            return
                "You slept an average of \(current) a night over the last 7 days (\(days) \(plural(days, "night")) recorded)."
                + (previous.map { " The week before, the average was \($0)." } ?? "")
        case .workoutCount:
            let count = FindingFormatter.rounded(average.thisWeek)
            return "You recorded \(current) \(plural(count, "workout")) over the last 7 days"
                + (previous.map { ", compared with \($0) the week before." } ?? ".")
        case .workoutMinutes:
            return "Your workouts added up to \(current) over the last 7 days"
                + (previous.map { ", compared with \($0) the week before." } ?? ".")
        default:
            if MetricWords.isDailyTotal(metric) {
                return
                    "You averaged \(current)\(MetricWords.amountSuffix(metric)) a day over the last 7 days (\(days) \(plural(days, "day")) recorded)."
                    + (previous.map { " The week before, the average was \($0)." } ?? "")
            }
            return
                "Your \(MetricWords.noun(metric)) averaged \(current) over the last 7 days (\(days) \(plural(days, "day")) recorded)."
                + (previous.map { " The week before, it averaged \($0)." } ?? "")
        }
    }

    // MARK: Patterns

    private static func sentence(for difference: GroupDifference) -> String {
        let with = format(difference.withConditionMedian, difference.outcome)
        let without = format(difference.withoutConditionMedian, difference.outcome)
        let counts = "\(difference.withConditionDays) and \(difference.withoutConditionDays)"
        let confidence = "\(difference.confidence.rawValue) confidence"

        switch difference.condition {
        case .shorterSleep:
            let threshold = FindingFormatter.duration(difference.conditionThreshold)
            return "On days after a night shorter than your median of \(threshold), "
                + "your \(MetricWords.noun(difference.outcome)) had a median of \(with), "
                + "compared with \(without) after longer nights (\(counts) days compared, \(confidence))."
        case .workoutDay:
            let minutes = FindingFormatter.rounded(difference.conditionThreshold)
            let outcome =
                difference.outcome == .sleepDuration ? "you slept" : "your \(MetricWords.noun(difference.outcome)) had"
            return "On nights after a day with at least \(minutes) minutes of workouts, "
                + "\(outcome) a median of \(with), "
                + "compared with \(without) after days without a workout (\(counts) nights compared, \(confidence))."
        }
    }

    private static func sentence(for correlation: Correlation) -> String {
        let x = correlation.x
        let highCondition: String
        let lowCondition: String
        if correlation.split == .noneVersusSome && correlation.lowGroupMaxX == 0 {
            highCondition = "on days with any \(MetricWords.noun(x))"
            lowCondition = "on days with no \(MetricWords.noun(x))"
        } else {
            highCondition = condition(x, format(correlation.highGroupMinX, x), "or more")
            lowCondition = condition(x, format(correlation.lowGroupMaxX, x), "or less")
        }
        let highY = format(correlation.highGroupMedianY, correlation.y)
        let lowY = format(correlation.lowGroupMedianY, correlation.y)
        let outcome: String =
            if correlation.y == .sleepDuration {
                "you slept a median of \(highY)\(correlation.lag == 1 ? " the following night" : "")"
            } else {
                "your \(MetricWords.noun(correlation.y))\(correlation.lag == 1 ? " the next day" : "") had a median of \(highY)"
            }
        return "\(highCondition.capitalizedFirst), \(outcome), compared with \(lowY) \(lowCondition) "
            + "(\(correlation.days) days compared, \(correlation.confidence.rawValue) confidence)."
    }

    /// "on days with 180 mg or more of caffeine", "after a night of 7h 30m or more".
    private static func condition(_ metric: Metric, _ amount: String, _ comparison: String) -> String {
        if metric == .sleepDuration { return "after a night of \(amount) \(comparison)" }
        if MetricWords.isScale(metric) {
            return "on days with a \(MetricWords.noun(metric)) of \(amount) \(comparison)"
        }
        return "on days with \(amount) \(comparison)\(MetricWords.amountSuffix(metric))"
    }

    // MARK: Trends, anomalies, comparisons

    private static func sentence(for trend: Trend) -> String {
        let subject: String =
            switch trend.metric {
            case .sleepDuration: "your nightly sleep"
            case let metric where MetricWords.isDailyTotal(metric): "your daily \(MetricWords.noun(metric))"
            case let metric: "your \(MetricWords.noun(metric))"
            }
        return
            "Over the last \(trend.windowDays) days, \(subject) went from about \(format(trend.startValue, trend.metric)) "
            + "to about \(format(trend.endValue, trend.metric)) "
            + "(\(trend.days) days recorded, \(trend.confidence.rawValue) confidence)."
    }

    private static func sentence(for anomaly: Anomaly) -> String {
        let value = format(anomaly.value, anomaly.metric)
        let range = FindingFormatter.range(anomaly.usualLow, anomaly.usualHigh, anomaly.metric.unit)
        let side = anomaly.isAbove ? "above" : "below"
        let opening: String =
            if anomaly.metric == .sleepDuration {
                anomaly.daysAgo == 0 ? "Last night you slept \(value)" : "The night before last you slept \(value)"
            } else {
                "Your \(MetricWords.noun(anomaly.metric)) \(MetricWords.when(anomaly.daysAgo)) was \(value)"
            }
        return "\(opening), \(side) your usual range of \(range) over the previous \(anomaly.baselineDays) days."
    }

    private static func sentence(for comparison: DayComparison) -> String {
        let value = format(comparison.value, comparison.metric)
        let median = format(comparison.baselineMedian, comparison.metric)
        if comparison.metric == .sleepDuration {
            return "Last night you slept \(value). Your median over the previous \(comparison.baselineDays) "
                + "\(plural(comparison.baselineDays, "night")) is \(median)."
        }
        return "Your \(MetricWords.noun(comparison.metric)) \(MetricWords.when(comparison.daysAgo)) was \(value). "
            + "Your median over the previous \(comparison.baselineDays) \(plural(comparison.baselineDays, "day")) is \(median)."
    }

    // MARK: Helpers

    static func format(_ value: Double, _ metric: Metric) -> String {
        FindingFormatter.format(value, metric.unit)
    }

    private static func plural(_ count: Int, _ noun: String) -> String {
        count == 1 ? noun : noun + "s"
    }
}

extension String {
    fileprivate var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }

    fileprivate var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
