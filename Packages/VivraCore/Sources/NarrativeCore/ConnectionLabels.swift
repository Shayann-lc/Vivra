import Foundation
import InsightEngine

/// Every word on the Connections screens. Templates only, checked against
/// `StyleGuide` in tests; every number goes through `FindingFormatter`.
public enum ConnectionLabels {
    // MARK: Names

    /// A section of the "by outcome" view.
    public static func outcomeName(_ metric: Metric) -> String {
        switch metric {
        case .sleepDuration: "Sleep"
        case .heartRateVariability: "Heart rate variability (SDNN)"
        default: MetricWords.noun(metric).capitalizedFirst
        }
    }

    /// A row's behaviour, and a section of the "by habit" view.
    public static func behaviourName(_ behaviour: ConnectionBehaviour) -> String {
        habitName(behaviour.metric)
    }

    public static func habitName(_ metric: Metric) -> String {
        switch metric {
        case .sleepDuration: "Sleep"
        case .workoutMinutes: "Workouts"
        case .steps: "Steps"
        case .exerciseMinutes: "Exercise minutes"
        default: MetricWords.noun(metric).capitalizedFirst
        }
    }

    /// When the outcome is measured, relative to the behaviour.
    public static func timing(_ row: ConnectionBoard.Row) -> String {
        if row.outcome == .sleepDuration && row.lag == 1 { return "night after" }
        if row.behaviour.metric == .sleepDuration && row.lag == 0 { return "day after" }
        return row.lag == 0 ? "same day" : "next day"
    }

    /// "Caffeine and sleep the night after".
    public static func title(_ row: ConnectionBoard.Row) -> String {
        "\(behaviourName(row.behaviour)) and \(outcomeName(row.outcome).lowercasedFirstWord) the \(timing(row))"
    }

    // MARK: Found rows

    /// The two groups, as less/none and more/some.
    public static func groups(_ finding: Finding) -> (less: String, more: String)? {
        switch finding.detail {
        case .correlation(let correlation):
            if correlation.split == .noneVersusSome && correlation.lowGroupMaxX == 0 { return ("none", "any") }
            let unit = correlation.x.unit
            return (
                "\(FindingFormatter.format(correlation.lowGroupMaxX, unit)) or less",
                "\(FindingFormatter.format(correlation.highGroupMinX, unit)) or more"
            )
        case .groupDifference(let difference):
            switch difference.condition {
            case .shorterSleep:
                let median = FindingFormatter.duration(difference.conditionThreshold)
                return ("under \(median)", "\(median) or more")
            case .workoutDay:
                let minutes = FindingFormatter.format(difference.conditionThreshold, .minutes)
                return ("no workout", "\(minutes) or more")
            }
        default:
            return nil
        }
    }

    public static func value(_ value: Double, _ metric: Metric) -> String {
        FindingFormatter.format(value, metric.unit)
    }

    /// "none: 7h 10m · any: 6h 50m".
    public static func comparison(_ row: ConnectionBoard.Row) -> String? {
        guard let finding = row.status.finding, let comparison = row.comparison, let groups = groups(finding) else {
            return nil
        }
        return "\(groups.less): \(value(comparison.lessMedian, row.outcome)) · "
            + "\(groups.more): \(value(comparison.moreMedian, row.outcome))"
    }

    /// "41 and 32 days · medium confidence".
    public static func evidence(_ row: ConnectionBoard.Row) -> String? {
        guard let comparison = row.comparison else { return nil }
        return "\(comparison.lessDays) and \(comparison.moreDays) days · \(comparison.confidence.rawValue) confidence"
    }

    /// "Last night 6h 40m", "Yesterday 2 drinks".
    public static func latest(_ latest: ConnectionBoard.Latest, behaviour: ConnectionBehaviour) -> String {
        let when =
            behaviour.metric == .sleepDuration && latest.daysAgo == 0
            ? "Last night" : MetricWords.when(latest.daysAgo).capitalizedFirst
        return "\(when) \(value(latest.value, behaviour.metric))"
    }

    // MARK: Other statuses

    /// Why a row shows no comparison. Never includes outcome values.
    public static func status(_ row: ConnectionBoard.Row) -> String {
        switch row.status {
        case .found: confidenceText(row.comparison?.confidence ?? .low)
        case .noClearPattern(let days): "No clear pattern in \(days) days"
        case .notEnoughVariety: "Not enough variety to compare"
        case .needsMoreDays(let have, let need): "Needs more days (\(have) of \(need))"
        case .notRecorded(let metric): "\(habitName(metric)) not recorded in the last 90 days"
        }
    }

    public static func confidenceText(_ confidence: Confidence) -> String {
        "\(confidence.rawValue.capitalizedFirst) confidence"
    }

    // MARK: Sections and summary

    /// "Usual 7h 0m, range 6h 20m–7h 45m".
    public static func usual(_ usual: ConnectionBoard.Usual, _ metric: Metric) -> String {
        "Usual \(value(usual.median, metric)), range \(FindingFormatter.range(usual.low, usual.high, metric.unit))"
    }

    /// "Last 90 days: 4 found, 9 with no clear pattern, 4 without enough data yet".
    public static func summary(_ board: ConnectionBoard) -> String {
        var found = 0
        var unclear = 0
        var waiting = 0
        for row in board.rows {
            switch row.status {
            case .found: found += 1
            case .noClearPattern, .notEnoughVariety: unclear += 1
            case .needsMoreDays, .notRecorded: waiting += 1
            }
        }
        var parts = ["\(found) found"]
        if unclear > 0 { parts.append("\(unclear) with no clear pattern") }
        if waiting > 0 { parts.append("\(waiting) without enough data yet") }
        return "Last \(board.windowDays) days: " + parts.joined(separator: ", ")
    }

    // MARK: Detail

    /// "How this was worked out", one line each.
    public static func method(_ finding: Finding) -> [String] {
        switch finding.detail {
        case .correlation(let correlation):
            let split =
                correlation.split == .noneVersusSome
                ? "Days with no \(MetricWords.noun(correlation.x)) against days with some."
                : "The third of days with the least \(MetricWords.noun(correlation.x)) against the third with the most."
            let difference = abs(correlation.highGroupMedianY - correlation.lowGroupMedianY)
            return [
                "Days compared: \(correlation.days).",
                split,
                "Difference between the two medians: \(value(difference, correlation.y)).",
                "Vivra checks \(PatternCatalog.correlations.count + 2) connections together, so a pattern is "
                    + "only shown when it's unlikely to be chance across all of them.",
            ]
        case .groupDifference(let difference):
            let low = min(abs(difference.differenceLow), abs(difference.differenceHigh))
            let high = max(abs(difference.differenceLow), abs(difference.differenceHigh))
            return [
                "Days compared: \(difference.withConditionDays) and \(difference.withoutConditionDays).",
                "Difference between the two medians: \(value(abs(difference.difference), difference.outcome)), "
                    + "95% range \(FindingFormatter.range(low, high, difference.outcome.unit)).",
                "Vivra checks \(PatternCatalog.correlations.count + 2) connections together, so a pattern is "
                    + "only shown when it's unlikely to be chance across all of them.",
            ]
        default:
            return []
        }
    }

    // MARK: Accessibility

    /// One sentence per row for VoiceOver.
    public static func accessibilitySentence(_ row: ConnectionBoard.Row) -> String {
        let subject = title(row)
        guard let finding = row.status.finding, let comparison = row.comparison, let groups = groups(finding) else {
            return "\(subject): \(status(row).lowercasedFirstWord)."
        }
        var sentence =
            "\(subject): with \(groups.less), a median of \(value(comparison.lessMedian, row.outcome)) "
            + "over \(comparison.lessDays) days; with \(groups.more), a median of "
            + "\(value(comparison.moreMedian, row.outcome)) over \(comparison.moreDays) days. "
            + "\(confidenceText(comparison.confidence))."
        if let latest = row.latest {
            let side = latest.side == .less ? groups.less : groups.more
            sentence += " \(self.latest(latest, behaviour: row.behaviour)), in the \(side) group."
        }
        return sentence
    }

    /// Where a value sits against the person's usual range, for VoiceOver.
    public static func rangePosition(_ value: Double, low: Double, high: Double) -> String {
        value < low ? "below your usual range" : value > high ? "above your usual range" : "within your usual range"
    }

    /// Under the 28-day timeline.
    public static func timelineNote(_ row: ConnectionBoard.Row) -> String {
        row.lag == 0 && row.behaviour.metric != .sleepDuration
            ? "Both are shown on the day they were recorded."
            : "Each \(MetricWords.noun(row.outcome)) value is shown on the day of the "
                + "\(MetricWords.noun(row.behaviour.metric)) it's compared with."
    }

    // MARK: Fixed text

    /// Under the list, and in "How Connections works".
    public static let footer =
        "These are things that went together in your data. Other things often change on the same days too."

    public static let explainer: [String] = [
        "Connections puts each habit next to an outcome, using your own last 90 days.",
        "The hollow dot is the outcome's median on days with less or none of the habit. The filled dot is "
            + "the median on days with more or some. The shaded band is your usual range.",
        "Vivra compares once there are 14 days with both, and only shows a connection when it's "
            + "unlikely to be chance. It says when it found nothing clear, which is common.",
        "These are things that went together, not reasons. Other things often change on the same days too.",
    ]

    /// Shown while every row is waiting for more data.
    public static let lowDataNote =
        "Vivra compares a habit with an outcome once there are 14 days with both. "
        + "Logging mood and drinks in Quick Log adds more to compare."

    public static let noneFoundNote =
        "Vivra looked at every connection and none was clear enough to show. That's common, and useful to know."
}

extension String {
    fileprivate var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }

    /// Lowercases the first word unless it's an abbreviation ("SDNN").
    fileprivate var lowercasedFirstWord: String {
        guard let first, !(dropFirst().first?.isUppercase ?? false) else { return self }
        return first.lowercased() + dropFirst()
    }
}
