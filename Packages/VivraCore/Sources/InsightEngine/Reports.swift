import Foundation
import VivraModel

public enum WeeklyReportBuilder {
    /// Daily metrics in the weekly summary (means of daily values).
    static let averagedMetrics: [Metric] = [
        .sleepDuration, .restingHeartRate, .heartRateVariability, .walkingHeartRateAverage, .vo2Max, .steps,
        .exerciseMinutes, .mindfulMinutes, .mood, .energyLevel, .stressLevel, .water, .caffeine, .alcohol, .weight,
        .respiratoryRate, .bloodOxygen,
    ]

    /// Builds the report for the 7 complete days before `clock.now`:
    /// patterns, then trends, then weekly averages.
    public static func build(
        _ dataset: HealthDataset,
        clock: any Clock,
        calendar: DayCalendar,
        sourcePolicy: SourcePolicy = .default
    ) -> InsightReport {
        let metrics = DailyMetrics.build(dataset, calendar: calendar, sourcePolicy: sourcePolicy)
        let today = calendar.day(clock.now)
        let thisWeek = (1...7).map { calendar.adding(days: -$0, to: today) }
        let previousWeek = (8...14).map { calendar.adding(days: -$0, to: today) }

        return InsightReport(
            kind: .weekly,
            periodStart: thisWeek.last!,
            periodEnd: thisWeek.first!,
            findings: PatternFinder.findings(metrics: metrics, today: today, calendar: calendar)
                + TrendFinder.findings(metrics: metrics, today: today, calendar: calendar)
                + weeklyFindings(metrics: metrics, thisWeek: thisWeek, previousWeek: previousWeek)
        )
    }

    static func weeklyFindings(metrics: DailyMetrics, thisWeek: [Day], previousWeek: [Day]) -> [Finding] {
        var findings: [Finding] = []
        for metric in averagedMetrics {
            let current = thisWeek.compactMap { metrics.value(metric, on: $0) }
            guard current.count >= PatternRules.minimumDaysPerWeek else { continue }
            let previous = previousWeek.compactMap { metrics.value(metric, on: $0) }
            let average = WeeklyAverage(
                metric: metric,
                thisWeek: Statistics.mean(current)!,
                thisWeekDays: current.count,
                previousWeek: previous.count >= PatternRules.minimumDaysPerWeek ? Statistics.mean(previous) : nil,
                previousWeekDays: previous.count
            )
            findings.append(
                Finding(
                    id: "weekly.\(metric.rawValue)",
                    detail: .weeklyAverage(average),
                    suggestProfessional: metric.isOutsideTypicalRange(average.thisWeek)
                )
            )
        }

        if metrics.hasData(.workoutMinutes) {
            for metric in [Metric.workoutCount, .workoutMinutes] {
                let total = { (days: [Day]) in days.reduce(0) { $0 + (metrics.value(metric, on: $1) ?? 0) } }
                let average = WeeklyAverage(
                    metric: metric,
                    thisWeek: total(thisWeek),
                    thisWeekDays: 7,
                    previousWeek: total(previousWeek),
                    previousWeekDays: 7
                )
                findings.append(Finding(id: "weekly.\(metric.rawValue)", detail: .weeklyAverage(average)))
            }
        }
        return findings
    }
}

public enum DailyCheckInBuilder {
    static let baselineDays = 28
    static let minimumBaselineDays = 7

    /// Each metric with the days to try, most recent first.
    static let comparisons: [(metric: Metric, daysAgo: [Int])] = [
        (.sleepDuration, [0]),
        (.restingHeartRate, [0, 1]),
        (.heartRateVariability, [0, 1]),
        (.steps, [1]),
        (.exerciseMinutes, [1]),
        (.mood, [0, 1]),
    ]

    /// Today's check-in: recent values next to their 28-day medians, any
    /// anomalies, and the single highest-confidence pattern.
    public static func build(
        _ dataset: HealthDataset,
        clock: any Clock,
        calendar: DayCalendar,
        sourcePolicy: SourcePolicy = .default
    ) -> InsightReport {
        let metrics = DailyMetrics.build(dataset, calendar: calendar, sourcePolicy: sourcePolicy)
        let today = calendar.day(clock.now)
        let anomalies = AnomalyFinder.findings(metrics: metrics, today: today, calendar: calendar)
        let anomalous = Set(
            anomalies.compactMap { finding -> Metric? in
                if case .anomaly(let anomaly) = finding.detail { return anomaly.metric }
                return nil
            })

        var findings = anomalies
        for (metric, offsets) in comparisons where !anomalous.contains(metric) {
            for daysAgo in offsets {
                let day = calendar.adding(days: -daysAgo, to: today)
                guard let value = metrics.value(metric, on: day) else { continue }
                let baseline = (1...baselineDays).compactMap {
                    metrics.value(metric, on: calendar.adding(days: -$0, to: day))
                }
                guard baseline.count >= minimumBaselineDays else { break }
                let comparison = DayComparison(
                    metric: metric,
                    daysAgo: daysAgo,
                    value: value,
                    baselineMedian: Statistics.median(baseline)!,
                    baselineDays: baseline.count
                )
                findings.append(
                    Finding(
                        id: "today.\(metric.rawValue)",
                        detail: .dayComparison(comparison),
                        suggestProfessional: metric.isOutsideTypicalRange(value)
                    )
                )
                break
            }
        }
        if let pattern = PatternFinder.findings(metrics: metrics, today: today, calendar: calendar).first {
            findings.append(pattern)
        }
        return InsightReport(kind: .daily, periodStart: today, periodEnd: today, findings: findings)
    }
}

/// Every current pattern and trend, for the Patterns screen.
public enum PatternList {
    public static func build(
        _ dataset: HealthDataset,
        clock: any Clock,
        calendar: DayCalendar,
        sourcePolicy: SourcePolicy = .default
    ) -> [Finding] {
        let metrics = DailyMetrics.build(dataset, calendar: calendar, sourcePolicy: sourcePolicy)
        let today = calendar.day(clock.now)
        return
            (PatternFinder.findings(metrics: metrics, today: today, calendar: calendar)
            + TrendFinder.findings(metrics: metrics, today: today, calendar: calendar))
            .sorted(by: PatternFinder.byConfidence)
    }
}
