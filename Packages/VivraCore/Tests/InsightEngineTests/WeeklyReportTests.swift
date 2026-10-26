import Foundation
import Testing
import VivraModel

@testable import InsightEngine

@Suite struct WeeklyReportTests {
    private func build(
        sleep: [SleepInterval] = [],
        samples: [QuantitySample] = [],
        workouts: [Workout] = [],
        policy: SourcePolicy = .default
    ) -> WeeklyReport {
        WeeklyReportBuilder.build(
            sleepIntervals: sleep,
            samples: samples,
            workouts: workouts,
            clock: FixedClock(Fixtures.now),
            calendar: Fixtures.utc,
            sourcePolicy: policy
        )
    }

    private func weekly(_ report: WeeklyReport, _ metric: Metric) -> WeeklyAverage? {
        for finding in report.findings {
            if case .weeklyAverage(let average) = finding.detail, average.metric == metric { return average }
        }
        return nil
    }

    private func pattern(_ report: WeeklyReport, _ id: String) -> GroupDifference? {
        for finding in report.findings where finding.id == id {
            if case .groupDifference(let difference) = finding.detail { return difference }
        }
        return nil
    }

    @Test func windowIsTheSevenDaysBeforeToday() {
        let report = build()
        #expect(report.periodStart == Fixtures.daysAgo(7))
        #expect(report.periodEnd == Fixtures.daysAgo(1))
    }

    @Test func weeklyAveragesCompareWithThePreviousWeek() {
        let samples =
            (1...7).map { Fixtures.quantity(.restingHeartRate, day: Fixtures.daysAgo($0), value: 58) }
            + (8...14).map { Fixtures.quantity(.restingHeartRate, day: Fixtures.daysAgo($0), value: 61) }
            // Today's sample is outside the window.
            + [Fixtures.quantity(.restingHeartRate, day: Fixtures.today, value: 90)]
        let average = weekly(build(samples: samples), .restingHeartRate)
        #expect(
            average
                == WeeklyAverage(
                    metric: .restingHeartRate, thisWeek: 58, thisWeekDays: 7, previousWeek: 61, previousWeekDays: 7))
    }

    @Test func weeksWithTooFewDaysAreLeftOut() {
        let samples =
            (1...2).map { Fixtures.quantity(.heartRateVariabilitySDNN, day: Fixtures.daysAgo($0), value: 40) }
        #expect(weekly(build(samples: samples), .heartRateVariability) == nil)

        let enough =
            (1...3).map { Fixtures.quantity(.heartRateVariabilitySDNN, day: Fixtures.daysAgo($0), value: 40) }
            + [Fixtures.quantity(.heartRateVariabilitySDNN, day: Fixtures.daysAgo(9), value: 50)]
        let average = weekly(build(samples: enough), .heartRateVariability)
        #expect(average?.thisWeekDays == 3)
        #expect(average?.previousWeek == nil)
    }

    @Test func workoutTotalsCountZeroWeeks() {
        let workouts = [
            Fixtures.workout(day: Fixtures.daysAgo(2), minutes: 30),
            Fixtures.workout(day: Fixtures.daysAgo(3), minutes: 45),
        ]
        let report = build(workouts: workouts)
        #expect(weekly(report, .workoutCount)?.thisWeek == 2)
        #expect(weekly(report, .workoutMinutes)?.thisWeek == 75)
        #expect(weekly(report, .workoutMinutes)?.previousWeek == 0)
    }

    @Test func stravaWorkoutsAreExcludedByDefault() {
        let workouts = [Fixtures.workout(day: Fixtures.daysAgo(2), minutes: 30, source: Fixtures.strava)]
        #expect(weekly(build(workouts: workouts), .workoutCount) == nil)
        #expect(weekly(build(workouts: workouts, policy: .includeAll), .workoutCount)?.thisWeek == 1)
    }

    @Test func restingHeartRateOutsideTypicalRangeIsFlagged() {
        let samples = (1...7).map { Fixtures.quantity(.restingHeartRate, day: Fixtures.daysAgo($0), value: 104) }
        let finding = build(samples: samples).findings.first { $0.id == "weekly.restingHeartRate" }
        #expect(finding?.suggestProfessional == true)

        let typical = (1...7).map { Fixtures.quantity(.restingHeartRate, day: Fixtures.daysAgo($0), value: 62) }
        #expect(
            build(samples: typical).findings.first { $0.id == "weekly.restingHeartRate" }?.suggestProfessional == false)
    }

    /// 60 days: short nights (5.5–6 h) go with a resting HR around 64,
    /// longer nights (7.5–8 h) with around 58.
    @Test func shorterSleepPatternIsFoundWhenTheDataShowIt() throws {
        var sleep: [SleepInterval] = []
        var samples: [QuantitySample] = []
        for offset in 1...60 {
            let day = Fixtures.daysAgo(offset)
            let short = offset.isMultiple(of: 2)
            sleep.append(
                Fixtures.sleep(
                    wakeDay: day, hours: short ? 5.5 + Double(offset % 3) * 0.25 : 7.5 + Double(offset % 3) * 0.25))
            samples.append(
                Fixtures.quantity(
                    .restingHeartRate, day: day, value: short ? 64 + Double(offset % 3) : 58 + Double(offset % 3)))
        }
        let difference = try #require(
            pattern(build(sleep: sleep, samples: samples), "pattern.shorterSleep.restingHeartRate"))
        #expect(difference.withConditionDays == 30)
        #expect(difference.withoutConditionDays == 30)
        #expect(difference.difference == 6)
        #expect(difference.confidence == .high)
        #expect(difference.differenceLow > 0)
    }

    @Test func noPatternFromUnrelatedData() {
        var sleep: [SleepInterval] = []
        var samples: [QuantitySample] = []
        for offset in 1...60 {
            let day = Fixtures.daysAgo(offset)
            sleep.append(Fixtures.sleep(wakeDay: day, hours: 6 + Double(offset % 5) * 0.5))
            samples.append(Fixtures.quantity(.restingHeartRate, day: day, value: 58 + Double((offset * 7) % 4)))
        }
        #expect(pattern(build(sleep: sleep, samples: samples), "pattern.shorterSleep.restingHeartRate") == nil)
    }

    @Test func patternsNeedEnoughDays() {
        var sleep: [SleepInterval] = []
        var samples: [QuantitySample] = []
        for offset in 1...12 {
            let day = Fixtures.daysAgo(offset)
            let short = offset.isMultiple(of: 2)
            sleep.append(Fixtures.sleep(wakeDay: day, hours: short ? 5 : 8))
            samples.append(Fixtures.quantity(.restingHeartRate, day: day, value: short ? 66 : 56))
        }
        #expect(pattern(build(sleep: sleep, samples: samples), "pattern.shorterSleep.restingHeartRate") == nil)
    }

    @Test func workoutDayPatternUsesTheFollowingNight() throws {
        var sleep: [SleepInterval] = []
        var workouts: [Workout] = []
        // Workouts on even offsets; the night after (offset − 1) is longer.
        for offset in 2...61 {
            let day = Fixtures.daysAgo(offset)
            let workoutDay = offset.isMultiple(of: 2)
            if workoutDay { workouts.append(Fixtures.workout(day: day, minutes: 40)) }
            sleep.append(Fixtures.sleep(wakeDay: Fixtures.daysAgo(offset - 1), hours: workoutDay ? 7.75 : 7))
        }
        let difference = try #require(
            pattern(build(sleep: sleep, workouts: workouts), "pattern.workoutDay.sleepDuration"))
        #expect(difference.withConditionMedian == 7.75 * 3600)
        #expect(difference.withoutConditionMedian == 7 * 3600)
    }

    @Test func reportIsDeterministic() {
        var sleep: [SleepInterval] = []
        var samples: [QuantitySample] = []
        for offset in 1...40 {
            let day = Fixtures.daysAgo(offset)
            sleep.append(Fixtures.sleep(wakeDay: day, hours: 5 + Double(offset % 7) * 0.5))
            samples.append(Fixtures.quantity(.restingHeartRate, day: day, value: 70 - Double(offset % 7)))
        }
        #expect(build(sleep: sleep, samples: samples) == build(sleep: sleep, samples: samples))
    }
}
