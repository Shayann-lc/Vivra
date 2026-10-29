import Foundation
import InsightEngine
import NarrativeCore
import SyncCore
import VivraModel

/// One input to evaluate: the findings a report would hand to the narrator.
public struct EvalCase: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: ReportKind
    /// Already capped at `SummaryComposer.maximumFindings`, in priority order.
    public let findings: [Finding]

    public init(id: String, kind: ReportKind, findings: [Finding]) {
        self.id = id
        self.kind = kind
        self.findings = Array(findings.prefix(SummaryComposer.maximumFindings))
    }

    public var report: InsightReport {
        InsightReport(kind: kind, periodStart: EvalCorpus.today, periodEnd: EvalCorpus.today, findings: findings)
    }
}

/// The fixed set of eval cases. Deterministic: the same code always gives
/// the same cases, so results can be compared between runs.
public enum EvalCorpus {
    static let calendar = DayCalendar(timeZone: TimeZone(identifier: "UTC")!)
    /// Wednesday 1 April 2026.
    static let today = Day(year: 2026, month: 4, day: 1)

    /// Every case, built once (the seeded ones run the full insight engine).
    public static let all: [EvalCase] = cases()

    static func cases() -> [EvalCase] {
        seededCases() + handMadeCases() + researchCases()
    }

    // MARK: From sample data, through the real report builders

    /// Ten seeded people at different times of day, plus one with only ten
    /// days of history, each through all four report kinds.
    static func seededCases() -> [EvalCase] {
        var cases: [EvalCase] = []
        let people = (1...10).map { (seed: UInt64($0), days: 90) } + [(seed: 11, days: 10)]
        for person in people {
            let day = calendar.adding(days: Int(person.seed), to: today)
            let hour: Double = person.seed.isMultiple(of: 2) ? 20 : 9
            let now = calendar.start(of: day).addingTimeInterval(hour * 3600)
            let dataset = dataset(
                SampleData.generate(now: now, calendar: calendar, days: person.days, seed: person.seed))
            let clock = FixedClock(now)
            for kind in ReportKind.allCases {
                let report: InsightReport =
                    switch kind {
                    case .daily: DailyCheckInBuilder.build(dataset, clock: clock, calendar: calendar)
                    case .weekly: WeeklyReportBuilder.build(dataset, clock: clock, calendar: calendar)
                    case .monthly: MonthlyReportBuilder.build(dataset, clock: clock, calendar: calendar)
                    case .feelingOff: FeelingOffBuilder.build(dataset, clock: clock, calendar: calendar)
                    }
                let history = person.days == 90 ? "" : "-\(person.days)d"
                cases.append(
                    EvalCase(id: "seed\(person.seed)\(history)-\(kind.rawValue)", kind: kind, findings: report.findings)
                )
            }
        }
        return cases
    }

    /// The dataset the app would load from the store for this data.
    static func dataset(_ data: SampleData) -> HealthDataset {
        let batches = data.batches.map(\.batch)
        let quantities = batches.flatMap(\.quantitySamples)
        return HealthDataset(
            sleepIntervals: batches.flatMap(\.sleepIntervals),
            samples: quantities.filter { HealthDataset.averageKinds.contains($0.kind) },
            dailySourceTotals: .totals(from: quantities, calendar: calendar),
            workouts: batches.flatMap(\.workouts),
            logs: data.logs
        )
    }

    // MARK: Hand-made findings

    /// Every finding type, rises and falls, extremes and single-finding
    /// reports, so coverage doesn't depend on what the sample data happens
    /// to produce.
    static func handMadeCases() -> [EvalCase] {
        let sleepShort = Anomaly(
            metric: .sleepDuration, daysAgo: 0, value: 3.5 * 3600, usualLow: 6.4 * 3600,
            usualHigh: 7.9 * 3600, baselineDays: 28)
        let restingHigh = Anomaly(
            metric: .restingHeartRate, daysAgo: 1, value: 74, usualLow: 54, usualHigh: 61,
            baselineDays: 28)
        let stepsRise = Trend(
            metric: .steps, windowDays: 90, startValue: 6_200, endValue: 9_800, days: 84,
            pValue: 0.001, adjustedPValue: 0.004, confidence: .high)
        let hrvFall = Trend(
            metric: .heartRateVariability, windowDays: 90, startValue: 58, endValue: 44, days: 80,
            pValue: 0.01, adjustedPValue: 0.03, confidence: .medium)
        let sleepDay = DayComparison(
            metric: .sleepDuration, daysAgo: 0, value: 8.2 * 3600,
            baselineMedian: 7.1 * 3600, baselineDays: 28)
        let moodDay = DayComparison(metric: .mood, daysAgo: 1, value: 2, baselineMedian: 4, baselineDays: 21)
        let weeklyUp = WeeklyAverage(
            metric: .exerciseMinutes, thisWeek: 48, thisWeekDays: 7, previousWeek: 22,
            previousWeekDays: 7)
        let weeklyDown = WeeklyAverage(
            metric: .sleepDuration, thisWeek: 6.4 * 3600, thisWeekDays: 6,
            previousWeek: 7.2 * 3600, previousWeekDays: 7)
        let weeklyNew = WeeklyAverage(
            metric: .caffeine, thisWeek: 190, thisWeekDays: 5, previousWeek: nil,
            previousWeekDays: 1)
        let workouts = WeeklyAverage(
            metric: .workoutCount, thisWeek: 1, thisWeekDays: 7, previousWeek: 4,
            previousWeekDays: 7)
        let monthUp = PeriodAverage(
            metric: .weight, periodDays: 30, value: 72.4, valueDays: 12, previous: 71.8,
            previousDays: 10)
        let monthDown = PeriodAverage(
            metric: .alcohol, periodDays: 30, value: 0.4, valueDays: 25, previous: 1.2,
            previousDays: 26)
        let shortSleepHeart = GroupDifference(
            condition: .shorterSleep, conditionThreshold: 7.1 * 3600,
            outcome: .restingHeartRate, withConditionMedian: 60, withoutConditionMedian: 57, withConditionDays: 41,
            withoutConditionDays: 44, differenceLow: 1, differenceHigh: 5, pValue: 0.001, adjustedPValue: 0.004,
            confidence: .high)
        let workoutSleep = GroupDifference(
            condition: .workoutDay, conditionThreshold: 20, outcome: .sleepDuration,
            withConditionMedian: 7.5 * 3600, withoutConditionMedian: 7.0 * 3600, withConditionDays: 30,
            withoutConditionDays: 52, differenceLow: 600, differenceHigh: 2_400, pValue: 0.02, adjustedPValue: 0.05,
            confidence: .medium)
        let caffeineSleep = Correlation(
            x: .caffeine, y: .sleepDuration, lag: 1, rho: -0.42, rhoLow: -0.58,
            rhoHigh: -0.23, days: 84, pValue: 0.0005, adjustedPValue: 0.003, confidence: .high, split: .thirds,
            lowGroupMaxX: 95, highGroupMinX: 190, lowGroupMedianY: 7.4 * 3600, highGroupMedianY: 6.6 * 3600,
            lowGroupDays: 28, highGroupDays: 28)
        let alcoholHrv = Correlation(
            x: .alcohol, y: .heartRateVariability, lag: 1, rho: -0.35, rhoLow: -0.52,
            rhoHigh: -0.15, days: 88, pValue: 0.001, adjustedPValue: 0.006, confidence: .medium,
            split: .noneVersusSome, lowGroupMaxX: 0, highGroupMinX: 1, lowGroupMedianY: 51, highGroupMedianY: 43,
            lowGroupDays: 66, highGroupDays: 22)
        let sleepMood = Correlation(
            x: .sleepDuration, y: .mood, lag: 0, rho: 0.38, rhoLow: 0.18, rhoHigh: 0.55,
            days: 70, pValue: 0.001, adjustedPValue: 0.005, confidence: .high, split: .thirds,
            lowGroupMaxX: 6.6 * 3600, highGroupMinX: 7.5 * 3600, lowGroupMedianY: 3, highGroupMedianY: 4,
            lowGroupDays: 23, highGroupDays: 23)

        func finding(_ id: String, _ detail: FindingDetail, professional: Bool = false) -> Finding {
            Finding(id: id, detail: detail, suggestProfessional: professional)
        }
        let anomalyShort = finding("anomaly-sleep", .anomaly(sleepShort))
        let anomalyHigh = finding("anomaly-resting", .anomaly(restingHigh), professional: true)
        let trendUp = finding("trend-steps", .trend(stepsRise))
        let trendDown = finding("trend-hrv", .trend(hrvFall))
        let daySleep = finding("day-sleep", .dayComparison(sleepDay))
        let dayMood = finding("day-mood", .dayComparison(moodDay))
        let averageUp = finding("weekly-exercise", .weeklyAverage(weeklyUp))
        let averageDown = finding("weekly-sleep", .weeklyAverage(weeklyDown))
        let averageNew = finding("weekly-caffeine", .weeklyAverage(weeklyNew))
        let workoutCount = finding("weekly-workouts", .weeklyAverage(workouts))
        let periodUp = finding("month-weight", .periodAverage(monthUp))
        let periodDown = finding("month-alcohol", .periodAverage(monthDown))
        let difference = finding("pattern-short-sleep-resting", .groupDifference(shortSleepHeart))
        let workoutDifference = finding("pattern-workout-sleep", .groupDifference(workoutSleep))
        let thirds = finding("pattern-caffeine-sleep", .correlation(caffeineSleep))
        let noneVersusSome = finding("pattern-alcohol-hrv", .correlation(alcoholHrv))
        let sameDay = finding("pattern-sleep-mood", .correlation(sleepMood))
        let appliesCorrelation = finding(
            "applies-caffeine",
            .applicablePattern(
                ApplicablePattern(
                    basis: .correlation(caffeineSleep),
                    metric: .caffeine, daysAgo: 1, value: 285)))
        let appliesDifference = finding(
            "applies-short-sleep",
            .applicablePattern(
                ApplicablePattern(
                    basis: .groupDifference(shortSleepHeart),
                    metric: .sleepDuration, daysAgo: 0, value: 5.9 * 3600)))

        return [
            EvalCase(id: "hand-daily-mixed", kind: .daily, findings: [daySleep, dayMood, anomalyHigh, thirds]),
            EvalCase(id: "hand-daily-short-night", kind: .daily, findings: [anomalyShort, daySleep]),
            EvalCase(id: "hand-daily-single", kind: .daily, findings: [dayMood]),
            EvalCase(id: "hand-daily-empty", kind: .daily, findings: []),
            EvalCase(
                id: "hand-weekly-full", kind: .weekly,
                findings: [difference, thirds, trendUp, trendDown, averageUp, averageDown, averageNew, workoutCount]),
            EvalCase(id: "hand-weekly-averages", kind: .weekly, findings: [averageUp, averageDown, workoutCount]),
            EvalCase(id: "hand-weekly-single-pattern", kind: .weekly, findings: [noneVersusSome]),
            EvalCase(id: "hand-weekly-empty", kind: .weekly, findings: []),
            EvalCase(
                id: "hand-monthly-full", kind: .monthly,
                findings: [workoutDifference, sameDay, trendDown, periodUp, periodDown]),
            EvalCase(id: "hand-monthly-trends", kind: .monthly, findings: [trendUp, trendDown]),
            EvalCase(id: "hand-monthly-empty", kind: .monthly, findings: []),
            EvalCase(
                id: "hand-feeling-off-mixed", kind: .feelingOff,
                findings: [anomalyShort, anomalyHigh, appliesCorrelation, appliesDifference]),
            EvalCase(
                id: "hand-feeling-off-patterns", kind: .feelingOff, findings: [appliesCorrelation, appliesDifference]),
            EvalCase(id: "hand-feeling-off-single", kind: .feelingOff, findings: [anomalyHigh]),
            EvalCase(id: "hand-feeling-off-empty", kind: .feelingOff, findings: []),
            EvalCase(
                id: "hand-weekly-extremes", kind: .weekly,
                findings: [anomalyShort, anomalyHigh, noneVersusSome, sameDay, workoutDifference]),
        ]
    }

    // MARK: Research notes (PLAN Phase 8)

    /// Patterns that agree with their card, differ, match mixed research or
    /// an indirect card, fall below the confidence gate, exceed the cap of
    /// three, appear in reports that never show notes, or have only a
    /// record-only card.
    static func researchCases() -> [EvalCase] {
        func pattern(
            _ id: String, _ x: Metric, _ y: Metric, lag: Int, low: Double, high: Double,
            confidence: Confidence = .medium
        ) -> Finding {
            Finding(
                id: id,
                detail: .correlation(
                    Correlation(
                        x: x, y: y, lag: lag, rho: high > low ? 0.4 : -0.4, rhoLow: 0.2, rhoHigh: 0.6, days: 72,
                        pValue: 0.001, adjustedPValue: 0.01, confidence: confidence, split: .thirds,
                        lowGroupMaxX: x == .sleepDuration ? 6.6 * 3600 : 1,
                        highGroupMinX: x == .sleepDuration ? 7.5 * 3600 : 2, lowGroupMedianY: low,
                        highGroupMedianY: high, lowGroupDays: 24, highGroupDays: 24)))
        }
        let hour = 3600.0
        let alcoholHrvLower = pattern(
            "research-alcohol-hrv", .alcohol, .heartRateVariability, lag: 1, low: 51, high: 43)
        let alcoholHrvHigher = pattern(
            "research-alcohol-hrv-differs", .alcohol, .heartRateVariability, lag: 1, low: 43, high: 51)
        let alcoholSleep = pattern(
            "research-alcohol-sleep", .alcohol, .sleepDuration, lag: 1, low: 7.2 * hour, high: 6.7 * hour)
        let mindfulSleep = pattern(
            "research-mindful-sleep", .mindfulMinutes, .sleepDuration, lag: 1, low: 6.9 * hour, high: 7.3 * hour)
        let caffeineSleep = pattern(
            "research-caffeine-sleep", .caffeine, .sleepDuration, lag: 1, low: 7.4 * hour, high: 6.8 * hour)
        let sleepMood = pattern("research-sleep-mood", .sleepDuration, .mood, lag: 0, low: 3, high: 4)
        let sleepEnergy = pattern("research-sleep-energy", .sleepDuration, .energyLevel, lag: 0, low: 3, high: 4)
        let stepsMood = pattern("research-steps-mood", .steps, .mood, lag: 0, low: 3, high: 4)
        let stepsSleep = pattern(
            "research-steps-sleep", .steps, .sleepDuration, lag: 1, low: 7.3 * hour, high: 7.0 * hour)
        let lowConfidence = pattern(
            "research-low-confidence", .alcohol, .heartRateVariability, lag: 1, low: 51, high: 43, confidence: .low)
        let workoutSleep = Finding(
            id: "research-workout-sleep",
            detail: .groupDifference(
                GroupDifference(
                    condition: .workoutDay, conditionThreshold: 20, outcome: .sleepDuration,
                    withConditionMedian: 7.5 * hour, withoutConditionMedian: 7.0 * hour, withConditionDays: 30,
                    withoutConditionDays: 52, differenceLow: 600, differenceHigh: 2_400, pValue: 0.02,
                    adjustedPValue: 0.05, confidence: .medium)))
        let shorterSleep = Finding(
            id: "research-shorter-sleep",
            detail: .groupDifference(
                GroupDifference(
                    condition: .shorterSleep, conditionThreshold: 7.1 * hour, outcome: .restingHeartRate,
                    withConditionMedian: 60, withoutConditionMedian: 57, withConditionDays: 41,
                    withoutConditionDays: 44, differenceLow: 1, differenceHigh: 5, pValue: 0.001,
                    adjustedPValue: 0.004, confidence: .high)))
        let anomaly = Finding(
            id: "research-anomaly",
            detail: .anomaly(
                Anomaly(metric: .restingHeartRate, daysAgo: 0, value: 66, usualLow: 54, usualHigh: 60, baselineDays: 28)
            ))

        return [
            EvalCase(id: "research-agrees", kind: .weekly, findings: [alcoholHrvLower]),
            EvalCase(id: "research-differs", kind: .weekly, findings: [alcoholHrvHigher]),
            EvalCase(id: "research-mixed", kind: .monthly, findings: [alcoholSleep, stepsSleep]),
            EvalCase(id: "research-indirect", kind: .daily, findings: [mindfulSleep, sleepEnergy]),
            EvalCase(id: "research-low-confidence", kind: .weekly, findings: [lowConfidence]),
            EvalCase(id: "research-group", kind: .weekly, findings: [workoutSleep]),
            EvalCase(id: "research-record-only", kind: .weekly, findings: [shorterSleep]),
            EvalCase(id: "research-two-cards", kind: .monthly, findings: [sleepMood]),
            EvalCase(
                id: "research-cap", kind: .monthly,
                findings: [caffeineSleep, alcoholHrvLower, sleepMood, stepsMood, mindfulSleep]),
            EvalCase(id: "research-feeling-off", kind: .feelingOff, findings: [alcoholHrvLower, anomaly]),
            EvalCase(id: "research-anomaly", kind: .daily, findings: [anomaly]),
            EvalCase(id: "research-mixed-with-differs", kind: .weekly, findings: [alcoholHrvHigher, sleepMood]),
        ]
    }
}
