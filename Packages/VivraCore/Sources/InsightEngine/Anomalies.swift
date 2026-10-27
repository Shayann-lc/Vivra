import Foundation
import VivraModel

/// Recent values well outside the person's own usual range.
enum AnomalyFinder {
    static let baselineDays = 28
    static let minimumBaselineDays = 14
    /// Iglewicz & Hoaglin's cut-off for the modified z-score.
    static let threshold = 3.5

    /// Metrics checked for today (known by morning) and yesterday. Daily
    /// totals are only checked for yesterday, since today isn't over.
    static let todayAndYesterday: [Metric] = [
        .sleepDuration, .restingHeartRate, .heartRateVariability, .respiratoryRate, .bloodOxygen, .wristTemperature,
    ]
    static let yesterdayOnly: [Metric] = [.steps, .exerciseMinutes]

    static func findings(metrics daily: DailyMetrics, today: Day, calendar: DayCalendar) -> [Finding] {
        var findings: [Finding] = []
        for metric in todayAndYesterday + yesterdayOnly {
            let offsets = yesterdayOnly.contains(metric) ? [1] : [0, 1]
            // The most recent anomaly only.
            for daysAgo in offsets {
                if let anomaly = anomaly(metric, daysAgo: daysAgo, daily: daily, today: today, calendar: calendar) {
                    findings.append(
                        Finding(
                            id: "anomaly.\(metric.rawValue)",
                            detail: .anomaly(anomaly),
                            suggestProfessional: metric.isOutsideTypicalRange(anomaly.value)
                        )
                    )
                    break
                }
            }
        }
        return findings
    }

    static func anomaly(_ metric: Metric, daysAgo: Int, daily: DailyMetrics, today: Day, calendar: DayCalendar)
        -> Anomaly?
    {
        let day = calendar.adding(days: -daysAgo, to: today)
        guard let value = daily.value(metric, on: day) else { return nil }
        let baseline = (1...baselineDays).compactMap { daily.value(metric, on: calendar.adding(days: -$0, to: day)) }
        guard baseline.count >= minimumBaselineDays,
            let median = Statistics.median(baseline),
            let mad = Statistics.medianAbsoluteDeviation(baseline),
            mad > 0
        else { return nil }
        let z = (value - median) / (1.4826 * mad)
        guard abs(z) >= threshold, abs(value - median) >= metric.minimumEffect else { return nil }
        let sorted = baseline.sorted()
        return Anomaly(
            metric: metric,
            daysAgo: daysAgo,
            value: value,
            usualLow: Statistics.percentile(sorted, 0.1),
            usualHigh: Statistics.percentile(sorted, 0.9),
            baselineDays: baseline.count
        )
    }
}
