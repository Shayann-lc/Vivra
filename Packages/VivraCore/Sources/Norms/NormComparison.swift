import Foundation
import InsightEngine
import NarrativeCore

/// Where a value sits relative to published reference data. Neutral
/// positions only, never categories.
public enum NormComparison: Sendable, Equatable {
    public enum Placement: Sendable, Equatable {
        case below(Int)
        case at(Int)
        case between(Int, Int)
        case above(Int)
    }

    case percentile(Placement, norm: PercentileNorm, source: NormSource)
    case recommendation(RecommendationNorm, source: NormSource)
    case median(MedianNorm, source: NormSource)

    public var source: NormSource {
        switch self {
        case .percentile(_, _, let source), .recommendation(_, let source), .median(_, let source): source
        }
    }
}

public enum NormComparer {
    /// Comparisons for `value` of `metric`, for the person's age this year.
    public static func compare(
        _ metric: Metric,
        value: Double,
        profile: ComparisonProfile,
        year: Int,
        table: NormTable
    ) -> [NormComparison] {
        let age = profile.age(in: year)
        var results: [NormComparison] = []
        for norm in table.percentiles
        where norm.metric == metric && norm.group == profile.group && norm.ages.contains(age) {
            guard let source = table.source(norm.sourceID) else { continue }
            results.append(.percentile(placement(value, in: norm.points), norm: norm, source: source))
        }
        for norm in table.recommendations where norm.metric == metric && norm.ages.contains(age) {
            guard let source = table.source(norm.sourceID) else { continue }
            results.append(.recommendation(norm, source: source))
        }
        for norm in table.medians where norm.metric == metric && norm.group == profile.group && norm.ages.contains(age)
        {
            guard let source = table.source(norm.sourceID) else { continue }
            results.append(.median(norm, source: source))
        }
        return results
    }

    /// Values within half a unit of a published percentile count as "at" it,
    /// since tables are rounded.
    static func placement(_ value: Double, in points: [PercentilePoint]) -> NormComparison.Placement {
        let rounded = value.rounded()
        if let exact = points.last(where: { abs($0.value - rounded) < 0.5 }) { return .at(exact.percentile) }
        guard let first = points.first, let last = points.last else { return .at(50) }
        if rounded < first.value { return .below(first.percentile) }
        if rounded > last.value { return .above(last.percentile) }
        for (lower, upper) in zip(points, points.dropFirst()) where rounded > lower.value && rounded < upper.value {
            return .between(lower.percentile, upper.percentile)
        }
        return .at(last.percentile)
    }
}

/// Sentences for comparisons. Kept here so the wording sits with the data.
public enum NormText {
    /// `subject` names the person's value, e.g. "Your 28-day median of 58 bpm".
    public static func sentence(_ comparison: NormComparison, subject: String, valueText: String) -> String {
        switch comparison {
        case .percentile(let placement, let norm, let source):
            let position: String =
                switch placement {
                case .below(let p): "below the \(ordinal(p)) percentile"
                case .at(let p): "at about the \(ordinal(p)) percentile"
                case .between(let low, let high): "between the \(ordinal(low)) and \(ordinal(high)) percentiles"
                case .above(let p): "above the \(ordinal(p)) percentile"
                }
            return "\(subject) is \(position) for \(norm.group.rawValue) aged \(ages(norm.ages)) in \(source.name)."
        case .recommendation(let norm, let source):
            return "\(source.name.capitalizedFirst) recommend \(range(norm)) for adults aged \(ages(norm.ages)). "
                + "\(subject) is \(valueText)."
        case .median(let norm, let source):
            let median = FindingFormatter.format(norm.median, norm.metric.unit)
            return "The median for \(norm.group.rawValue) aged \(ages(norm.ages)) in \(source.name) is \(median). "
                + "\(subject) is \(valueText)."
        }
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String =
            switch (n % 10, n % 100) {
            case (_, 11...13): "th"
            case (1, _): "st"
            case (2, _): "nd"
            case (3, _): "rd"
            default: "th"
            }
        return "\(n)\(suffix)"
    }

    static func ages(_ range: ClosedRange<Int>) -> String {
        range.upperBound >= 100 ? "\(range.lowerBound) and over" : "\(range.lowerBound)–\(range.upperBound)"
    }

    static func range(_ norm: RecommendationNorm) -> String {
        let unit = norm.metric.unit
        func hours(_ value: Double) -> String {
            unit == .seconds ? "\(FindingFormatter.rounded(value / 3600)) hours" : FindingFormatter.format(value, unit)
        }
        switch (norm.minimum, norm.maximum) {
        case (let low?, let high?): return "\(hours(low))–\(hours(high))"
        case (let low?, nil): return "\(hours(low)) or more"
        case (nil, let high?): return "up to \(hours(high))"
        case (nil, nil): return ""
        }
    }
}

extension String {
    fileprivate var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
