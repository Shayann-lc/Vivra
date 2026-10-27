import Foundation
import Testing
import VivraModel

@testable import InsightEngine

@Suite struct MonthlyReportTests {
    @Test func averagesTheLastThirtyDaysAgainstTheThirtyBefore() throws {
        let samples =
            (1...30).map { Fixtures.quantity(.restingHeartRate, day: Fixtures.daysAgo($0), value: 58) }
            + (31...60).map { Fixtures.quantity(.restingHeartRate, day: Fixtures.daysAgo($0), value: 61) }
        let report = MonthlyReportBuilder.build(
            Fixtures.dataset(samples: samples), clock: Fixtures.clock, calendar: Fixtures.utc)

        #expect(report.kind == .monthly)
        #expect(report.periodStart == Fixtures.daysAgo(30))
        #expect(report.periodEnd == Fixtures.daysAgo(1))
        let finding = try #require(report.findings.first { $0.id == "monthly.restingHeartRate" })
        guard case .periodAverage(let average) = finding.detail else {
            Issue.record("Wrong kind")
            return
        }
        #expect(
            average
                == PeriodAverage(
                    metric: .restingHeartRate, periodDays: 30, value: 58, valueDays: 30, previous: 61, previousDays: 30)
        )
    }

    @Test func needsTenDaysInAPeriod() {
        let samples = (1...9).map { Fixtures.quantity(.heartRateVariabilitySDNN, day: Fixtures.daysAgo($0), value: 40) }
        let report = MonthlyReportBuilder.build(
            Fixtures.dataset(samples: samples), clock: Fixtures.clock, calendar: Fixtures.utc)
        #expect(!report.findings.contains { $0.id == "monthly.heartRateVariability" })
    }
}

@Suite struct FeelingOffTests {
    /// 60 days where caffeine on day t goes with shorter sleep that night,
    /// then 250 mg yesterday and a short night.
    private func caffeineHistory() -> HealthDataset {
        var logs: [LogEntry] = []
        var sleep: [SleepInterval] = []
        for offset in 2...61 {
            let caffeine = Double((offset * 37) % 300)
            logs.append(Fixtures.log(.drink, day: Fixtures.daysAgo(offset), drink: .coffee, amount: caffeine + 1))
            sleep.append(
                Fixtures.sleep(
                    wakeDay: Fixtures.daysAgo(offset - 1), hours: 8 - caffeine / 200 + Double(offset % 3) * 0.1))
        }
        logs.append(Fixtures.log(.drink, day: Fixtures.daysAgo(1), drink: .coffee, amount: 280))
        sleep.append(Fixtures.sleep(wakeDay: Fixtures.today, hours: 6.5))
        return Fixtures.dataset(sleep: sleep, logs: logs)
    }

    @Test func includesAPatternWhoseConditionWasMetYesterday() throws {
        let report = FeelingOffBuilder.build(caffeineHistory(), clock: Fixtures.clock, calendar: Fixtures.utc)

        #expect(report.kind == .feelingOff)
        let finding = try #require(report.findings.first { $0.id == "applies.pattern.caffeine.sleepDuration.lag1" })
        guard case .applicablePattern(let pattern) = finding.detail else {
            Issue.record("Wrong kind")
            return
        }
        #expect(pattern.metric == .caffeine)
        #expect(pattern.daysAgo == 1)
        #expect(pattern.value == 280)
    }

    @Test func includesValuesThatDifferFromTheUsual() {
        let report = FeelingOffBuilder.build(caffeineHistory(), clock: Fixtures.clock, calendar: Fixtures.utc)
        #expect(report.findings.contains { $0.id == "different.sleepDuration" || $0.id == "anomaly.sleepDuration" })
    }

    @Test func shorterSleepPatternAppliesAfterAShortNight() throws {
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
        sleep.append(Fixtures.sleep(wakeDay: Fixtures.today, hours: 5))

        let report = FeelingOffBuilder.build(
            Fixtures.dataset(sleep: sleep, samples: samples),
            clock: Fixtures.clock,
            calendar: Fixtures.utc
        )

        let finding = try #require(report.findings.first { $0.id == "applies.pattern.shorterSleep.restingHeartRate" })
        guard case .applicablePattern(let pattern) = finding.detail else {
            Issue.record("Wrong kind")
            return
        }
        #expect(pattern.value == 5 * 3600)
        #expect(pattern.daysAgo == 0)
    }

    @Test func nothingStandsOutWithoutData() {
        #expect(
            FeelingOffBuilder.build(HealthDataset(), clock: Fixtures.clock, calendar: Fixtures.utc).findings.isEmpty)
    }
}
