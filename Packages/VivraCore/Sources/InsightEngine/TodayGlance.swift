import Foundation
import VivraModel

/// The top of the Today screen: the latest value of a few metrics next to
/// the person's usual, plus one thing worth noticing. Numbers first, no
/// composite scores (docs/UX_RESEARCH.md).
public struct TodayGlance: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable {
        public let metric: Metric
        /// 0 today, 1 yesterday.
        public let daysAgo: Int
        public let value: Double
        /// True for a daily total that's still adding up (steps today).
        public let isSoFar: Bool
        /// Median of the previous 28 days, when at least 7 have data.
        public let usual: Double?
        public let usualLow: Double?
        public let usualHigh: Double?
        public let baselineDays: Int
        public var id: Metric { metric }
    }

    public let rows: [Row]
    /// The most notable unusual value, otherwise the highest-confidence pattern.
    public let worthNoticing: Finding?

    static let baselineDays = 28
    static let minimumBaselineDays = 7

    /// Each metric with the days to try, most recent first.
    static let metrics: [(metric: Metric, daysAgo: [Int])] = [
        (.sleepDuration, [0, 1]),
        (.restingHeartRate, [0, 1]),
        (.heartRateVariability, [0, 1]),
        (.steps, [0]),
        (.mood, [0]),
    ]

    public static func build(
        _ dataset: HealthDataset,
        clock: any Clock,
        calendar: DayCalendar,
        sourcePolicy: SourcePolicy = .default
    ) -> TodayGlance {
        let metrics = DailyMetrics.build(dataset, calendar: calendar, sourcePolicy: sourcePolicy)
        let today = calendar.day(clock.now)
        var rows: [Row] = []
        for (metric, offsets) in self.metrics {
            for daysAgo in offsets {
                let day = calendar.adding(days: -daysAgo, to: today)
                guard let value = metrics.values[metric]?[day] else { continue }
                let baseline = (1...baselineDays).compactMap {
                    metrics.value(metric, on: calendar.adding(days: -$0, to: day))
                }
                let soFar = daysAgo == 0 && metric == .steps
                let hasBaseline = baseline.count >= minimumBaselineDays && !soFar
                let sorted = baseline.sorted()
                rows.append(
                    Row(
                        metric: metric,
                        daysAgo: daysAgo,
                        value: value,
                        isSoFar: soFar,
                        usual: hasBaseline ? Statistics.median(baseline) : nil,
                        usualLow: hasBaseline ? Statistics.percentile(sorted, 0.1) : nil,
                        usualHigh: hasBaseline ? Statistics.percentile(sorted, 0.9) : nil,
                        baselineDays: baseline.count
                    )
                )
                break
            }
        }
        let worth =
            AnomalyFinder.findings(metrics: metrics, today: today, calendar: calendar).first
            ?? PatternFinder.findings(metrics: metrics, today: today, calendar: calendar).first
        return TodayGlance(rows: rows, worthNoticing: worth)
    }
}

/// A metric over the last 28 days, with the person's usual range.
public struct MetricHistory: Sendable, Equatable {
    public struct Point: Sendable, Equatable, Identifiable {
        public let day: Day
        public let value: Double
        public var id: Day { day }
    }

    public let metric: Metric
    /// Oldest first; days without data are left out.
    public let points: [Point]
    /// From complete days only (today is excluded while it's still going).
    public let median: Double?
    public let usualLow: Double?
    public let usualHigh: Double?
    public let completeDays: Int

    public static let windowDays = 28

    public static func build(
        _ metric: Metric,
        dataset: HealthDataset,
        clock: any Clock,
        calendar: DayCalendar,
        sourcePolicy: SourcePolicy = .includeAll
    ) -> MetricHistory {
        let metrics = DailyMetrics.build(dataset, calendar: calendar, sourcePolicy: sourcePolicy)
        let today = calendar.day(clock.now)
        let days = (0..<windowDays).reversed().map { calendar.adding(days: -$0, to: today) }
        let points = days.compactMap { day in metrics.value(metric, on: day).map { Point(day: day, value: $0) } }
        let complete = points.filter { $0.day < today }.map(\.value).sorted()
        let enough = complete.count >= TodayGlance.minimumBaselineDays
        return MetricHistory(
            metric: metric,
            points: points,
            median: enough ? Statistics.median(complete) : nil,
            usualLow: enough ? Statistics.percentile(complete, 0.1) : nil,
            usualHigh: enough ? Statistics.percentile(complete, 0.9) : nil,
            completeDays: complete.count
        )
    }
}
