import Foundation
import VivraModel

/// Steady changes over the last four weeks.
enum TrendFinder {
    static let windowDays = 28
    static let minimumDays = 14
    static let metrics: [Metric] = [
        .sleepDuration, .restingHeartRate, .heartRateVariability, .vo2Max, .steps, .exerciseMinutes, .weight, .mood,
    ]

    private struct Candidate {
        let metric: Metric
        let start: Double
        let end: Double
        let days: Int
        let pValue: Double
    }

    /// Uses the `windowDays` complete days before `today`.
    static func findings(metrics daily: DailyMetrics, today: Day, calendar: DayCalendar) -> [Finding] {
        let window = (1...windowDays).reversed().map { calendar.adding(days: -$0, to: today) }
        let candidates = metrics.compactMap { metric -> Candidate? in
            let points = window.enumerated().compactMap { index, day in
                daily.value(metric, on: day).map { (x: Double(index), y: $0) }
            }
            guard points.count >= minimumDays, let line = Statistics.theilSen(points) else { return nil }
            let start = line.intercept
            let end = line.intercept + line.slope * Double(windowDays - 1)
            guard abs(end - start) >= metric.minimumEffect else { return nil }
            return Candidate(
                metric: metric,
                start: start,
                end: end,
                days: points.count,
                pValue: Statistics.mannKendallPValue(points.map(\.y))
            )
        }

        let adjusted = Statistics.benjaminiHochberg(candidates.map(\.pValue))
        return zip(candidates, adjusted).compactMap { candidate, adjustedP in
            guard adjustedP <= PatternRules.falseDiscoveryRate else { return nil }
            let confidence: Confidence =
                if candidate.days >= 24 && adjustedP <= 0.01 {
                    .high
                } else if adjustedP <= 0.05 {
                    .medium
                } else {
                    .low
                }
            let trend = Trend(
                metric: candidate.metric,
                windowDays: windowDays,
                startValue: candidate.start,
                endValue: candidate.end,
                days: candidate.days,
                pValue: candidate.pValue,
                adjustedPValue: adjustedP,
                confidence: confidence
            )
            return Finding(id: "trend.\(candidate.metric.rawValue)", detail: .trend(trend))
        }
        .sorted(by: PatternFinder.byConfidence)
    }
}
