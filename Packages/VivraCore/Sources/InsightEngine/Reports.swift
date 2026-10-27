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

public enum MonthlyReportBuilder {
    public static let periodDays = 30
    /// A metric needs this many days in a period to be averaged.
    public static let minimumDays = 10

    /// The last 30 complete days: patterns, trends, then 30-day averages
    /// next to the 30 days before.
    public static func build(
        _ dataset: HealthDataset,
        clock: any Clock,
        calendar: DayCalendar,
        sourcePolicy: SourcePolicy = .default
    ) -> InsightReport {
        let metrics = DailyMetrics.build(dataset, calendar: calendar, sourcePolicy: sourcePolicy)
        let today = calendar.day(clock.now)
        let period = (1...periodDays).map { calendar.adding(days: -$0, to: today) }
        let previous = ((periodDays + 1)...(2 * periodDays)).map { calendar.adding(days: -$0, to: today) }

        var averages: [Finding] = []
        for metric in WeeklyReportBuilder.averagedMetrics {
            let current = period.compactMap { metrics.value(metric, on: $0) }
            guard current.count >= minimumDays else { continue }
            let before = previous.compactMap { metrics.value(metric, on: $0) }
            let average = PeriodAverage(
                metric: metric,
                periodDays: periodDays,
                value: Statistics.mean(current)!,
                valueDays: current.count,
                previous: before.count >= minimumDays ? Statistics.mean(before) : nil,
                previousDays: before.count
            )
            averages.append(
                Finding(
                    id: "monthly.\(metric.rawValue)",
                    detail: .periodAverage(average),
                    suggestProfessional: metric.isOutsideTypicalRange(average.value)
                )
            )
        }
        if metrics.hasData(.workoutMinutes) {
            for metric in [Metric.workoutCount, .workoutMinutes] {
                let total = { (days: [Day]) in days.reduce(0) { $0 + (metrics.value(metric, on: $1) ?? 0) } }
                let average = PeriodAverage(
                    metric: metric,
                    periodDays: periodDays,
                    value: total(period),
                    valueDays: periodDays,
                    previous: total(previous),
                    previousDays: periodDays
                )
                averages.append(Finding(id: "monthly.\(metric.rawValue)", detail: .periodAverage(average)))
            }
        }

        return InsightReport(
            kind: .monthly,
            periodStart: period.last!,
            periodEnd: period.first!,
            findings: PatternFinder.findings(metrics: metrics, today: today, calendar: calendar)
                + TrendFinder.findings(metrics: metrics, today: today, calendar: calendar) + averages
        )
    }
}

/// "Why do I feel off today?" Things that stood out, and known patterns whose
/// condition was met. Never a reason (docs/STYLE_GUIDE.md).
public enum FeelingOffBuilder {
    /// Metrics compared with their usual, with the days to try.
    static let comparisons: [(metric: Metric, daysAgo: [Int])] = [
        (.sleepDuration, [0]),
        (.restingHeartRate, [0, 1]),
        (.heartRateVariability, [0, 1]),
        (.mood, [0, 1]),
        (.energyLevel, [0, 1]),
        (.stressLevel, [0, 1]),
        (.steps, [1]),
        (.exerciseMinutes, [1]),
        (.caffeine, [1]),
        (.alcohol, [1]),
    ]

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
        let patterns = PatternFinder.findings(metrics: metrics, today: today, calendar: calendar)
        let applicable = patterns.compactMap {
            applicablePattern($0, metrics: metrics, today: today, calendar: calendar)
        }

        var differences: [Finding] = []
        for (metric, offsets) in comparisons where !anomalous.contains(metric) {
            for daysAgo in offsets {
                let day = calendar.adding(days: -daysAgo, to: today)
                guard let value = metrics.value(metric, on: day) else { continue }
                let baseline = (1...DailyCheckInBuilder.baselineDays).compactMap {
                    metrics.value(metric, on: calendar.adding(days: -$0, to: day))
                }
                guard baseline.count >= DailyCheckInBuilder.minimumBaselineDays else { break }
                let median = Statistics.median(baseline)!
                if abs(value - median) >= metric.minimumEffect {
                    differences.append(
                        Finding(
                            id: "different.\(metric.rawValue)",
                            detail: .dayComparison(
                                DayComparison(
                                    metric: metric,
                                    daysAgo: daysAgo,
                                    value: value,
                                    baselineMedian: median,
                                    baselineDays: baseline.count
                                )
                            ),
                            suggestProfessional: metric.isOutsideTypicalRange(value)
                        )
                    )
                }
                break
            }
        }
        return InsightReport(
            kind: .feelingOff,
            periodStart: today,
            periodEnd: today,
            findings: anomalies + applicable + differences
        )
    }

    /// The pattern, if its condition was met by the most recent relevant day:
    /// for correlations, X in the low or high group on the day the pattern
    /// points to (today minus the lag); for group differences, the condition
    /// itself.
    static func applicablePattern(_ finding: Finding, metrics: DailyMetrics, today: Day, calendar: DayCalendar)
        -> Finding?
    {
        let applicable: ApplicablePattern
        switch finding.detail {
        case .correlation(let correlation):
            let day = calendar.adding(days: -correlation.lag, to: today)
            guard let value = metrics.value(correlation.x, on: day) else { return nil }
            let inLow = value <= correlation.lowGroupMaxX
            let inHigh =
                correlation.split == .noneVersusSome
                ? value > correlation.lowGroupMaxX : value >= correlation.highGroupMinX
            guard inLow || inHigh else { return nil }
            applicable = ApplicablePattern(
                basis: .correlation(correlation),
                metric: correlation.x,
                daysAgo: correlation.lag,
                value: value
            )
        case .groupDifference(let difference):
            switch difference.condition {
            case .shorterSleep:
                guard let sleep = metrics.value(.sleepDuration, on: today), sleep < difference.conditionThreshold
                else { return nil }
                applicable = ApplicablePattern(
                    basis: .groupDifference(difference),
                    metric: .sleepDuration,
                    daysAgo: 0,
                    value: sleep
                )
            case .workoutDay:
                let yesterday = calendar.adding(days: -1, to: today)
                guard let minutes = metrics.value(.workoutMinutes, on: yesterday),
                    minutes >= difference.conditionThreshold || minutes == 0
                else { return nil }
                applicable = ApplicablePattern(
                    basis: .groupDifference(difference),
                    metric: .workoutMinutes,
                    daysAgo: 1,
                    value: minutes
                )
            }
        default:
            return nil
        }
        return Finding(id: "applies.\(finding.id)", detail: .applicablePattern(applicable))
    }
}
