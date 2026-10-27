import Foundation
import Testing
import VivraModel

@testable import InsightEngine

@Suite struct CorrelationTests {
    private func patterns(_ dataset: HealthDataset) -> [Finding] {
        PatternList.build(dataset, clock: Fixtures.clock, calendar: Fixtures.utc, sourcePolicy: Fixtures.ownPolicy)
    }

    private func correlation(_ findings: [Finding], _ id: String) -> Correlation? {
        for finding in findings where finding.id == id {
            if case .correlation(let correlation) = finding.detail { return correlation }
        }
        return nil
    }

    /// Caffeine on day t, and the night after it: more caffeine, shorter sleep.
    @Test func findsCaffeineAndTheFollowingNight() throws {
        var logs: [LogEntry] = []
        var sleep: [SleepInterval] = []
        for offset in 2...61 {
            let caffeine = Double((offset * 37) % 300)
            logs.append(Fixtures.log(.drink, day: Fixtures.daysAgo(offset), drink: .coffee, amount: caffeine + 1))
            let hours = 8 - caffeine / 200 + Double(offset % 3) * 0.1
            sleep.append(Fixtures.sleep(wakeDay: Fixtures.daysAgo(offset - 1), hours: hours))
        }
        let found = try #require(
            correlation(patterns(Fixtures.dataset(sleep: sleep, logs: logs)), "pattern.caffeine.sleepDuration.lag1"))
        #expect(found.rho < -0.8)
        #expect(found.split == .thirds)
        #expect(found.highGroupMedianY < found.lowGroupMedianY)
        #expect(found.lowGroupMaxX < found.highGroupMinX)
        #expect(found.days == 60)
        #expect(found.confidence == .high)
    }

    /// Alcohol on a third of days, with lower HRV the next day.
    @Test func usesNoneVersusSomeWhenXIsOftenZero() throws {
        var logs: [LogEntry] = []
        var samples: [QuantitySample] = []
        for offset in 1...61 {
            let drinking = offset.isMultiple(of: 3)
            if drinking {
                logs.append(Fixtures.log(.drink, day: Fixtures.daysAgo(offset + 1), drink: .alcohol, amount: 2))
            }
            samples.append(
                Fixtures.quantity(
                    .heartRateVariabilitySDNN,
                    day: Fixtures.daysAgo(offset),
                    value: (drinking ? 36 : 46) + Double(offset % 4)
                )
            )
        }
        let found = try #require(
            correlation(
                patterns(Fixtures.dataset(samples: samples, logs: logs)), "pattern.alcohol.heartRateVariability.lag1")
        )
        #expect(found.split == .noneVersusSome)
        #expect(found.lowGroupMaxX == 0)
        #expect(found.highGroupMedianY < found.lowGroupMedianY)
    }

    @Test func findsNothingInUnrelatedData() {
        var logs: [LogEntry] = []
        var sleep: [SleepInterval] = []
        for offset in 1...60 {
            logs.append(Fixtures.log(.mood, day: Fixtures.daysAgo(offset), scale: 1 + (offset * 7) % 5))
            sleep.append(Fixtures.sleep(wakeDay: Fixtures.daysAgo(offset), hours: 6 + Double((offset * 3) % 4) * 0.5))
        }
        let found = patterns(Fixtures.dataset(sleep: sleep, logs: logs)).filter {
            if case .correlation = $0.detail { return true }
            return false
        }
        #expect(found.isEmpty)
    }

    @Test func stabilityComparesHalves() {
        let rising = (0..<10).map { (x: Double($0), y: Double($0)) }
        let falling = (0..<10).map { (x: Double($0), y: Double(10 - $0)) }
        #expect(PatternFinder.stability(rising + rising, rho: 0.9) == true)
        #expect(PatternFinder.stability(rising + falling, rho: 0.2) == false)
        #expect(PatternFinder.stability(Array(rising.prefix(12)), rho: 0.9) == nil)
    }

    @Test func concreteGroupsSplitIntoThirds() throws {
        let pairs = (1...15).map { (x: Double($0), y: Double($0) * 2) }
        let groups = try #require(PatternFinder.concreteGroups(pairs))
        #expect(groups.split == .thirds)
        #expect(groups.low.map(\.x) == [1, 2, 3, 4, 5])
        #expect(groups.high.map(\.x) == [11, 12, 13, 14, 15])
        // Too few distinct values to form non-overlapping groups.
        let lumpy = (1...14).map { (x: $0 < 3 ? 1.0 : 2.0, y: 0.0) }
        #expect(PatternFinder.concreteGroups(lumpy) == nil)
    }

    @Test func catalogueIdsAreUnique() {
        let ids = PatternCatalog.correlations.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}

@Suite struct TrendAndAnomalyTests {
    private func metrics(_ samples: [QuantitySample]) -> DailyMetrics {
        DailyMetrics.build(Fixtures.dataset(samples: samples), calendar: Fixtures.utc)
    }

    @Test func findsASteadyDeclineInRestingHeartRate() throws {
        let samples = (1...28).map { offset in
            // 62 bpm 28 days ago down to about 56 yesterday, with small wobble.
            Fixtures.quantity(
                .restingHeartRate,
                day: Fixtures.daysAgo(offset),
                value: 56 + Double(offset - 1) * 6 / 27 + Double(offset % 3) * 0.3
            )
        }
        let findings = TrendFinder.findings(metrics: metrics(samples), today: Fixtures.today, calendar: Fixtures.utc)
        let finding = try #require(findings.first { $0.id == "trend.restingHeartRate" })
        guard case .trend(let trend) = finding.detail else {
            Issue.record("Not a trend")
            return
        }
        #expect(abs(trend.startValue - 62.3) < 0.5)
        #expect(abs(trend.endValue - 56.3) < 0.5)
        #expect(trend.days == 28)
    }

    @Test func noTrendInFlatData() {
        let samples = (1...28).map {
            Fixtures.quantity(.restingHeartRate, day: Fixtures.daysAgo($0), value: 58 + Double(($0 * 5) % 3))
        }
        #expect(TrendFinder.findings(metrics: metrics(samples), today: Fixtures.today, calendar: Fixtures.utc).isEmpty)
    }

    @Test func flagsAValueFarOutsideTheUsualRange() throws {
        var samples = (1...28).map {
            Fixtures.quantity(.restingHeartRate, day: Fixtures.daysAgo($0), value: 57 + Double($0 % 5))
        }
        samples.append(Fixtures.quantity(.restingHeartRate, day: Fixtures.today, value: 75))
        let findings = AnomalyFinder.findings(metrics: metrics(samples), today: Fixtures.today, calendar: Fixtures.utc)
        let finding = try #require(findings.first { $0.id == "anomaly.restingHeartRate" })
        guard case .anomaly(let anomaly) = finding.detail else {
            Issue.record("Not an anomaly")
            return
        }
        #expect(anomaly.daysAgo == 0)
        #expect(anomaly.isAbove)
        #expect(anomaly.usualLow >= 57 && anomaly.usualHigh <= 61)
        #expect(!finding.suggestProfessional)
    }

    @Test func lowBloodOxygenAnomalyCarriesTheProfessionalNote() throws {
        var samples = (2...29).map {
            Fixtures.quantity(.oxygenSaturation, day: Fixtures.daysAgo($0), value: 95 + Double($0 % 3))
        }
        samples.append(Fixtures.quantity(.oxygenSaturation, day: Fixtures.daysAgo(1), value: 86))
        let findings = AnomalyFinder.findings(metrics: metrics(samples), today: Fixtures.today, calendar: Fixtures.utc)
        let finding = try #require(findings.first { $0.id == "anomaly.bloodOxygen" })
        #expect(finding.suggestProfessional)
    }

    @Test func noAnomalyWithinTheUsualRange() {
        var samples = (1...28).map {
            Fixtures.quantity(.restingHeartRate, day: Fixtures.daysAgo($0), value: 57 + Double($0 % 5))
        }
        samples.append(Fixtures.quantity(.restingHeartRate, day: Fixtures.today, value: 60))
        #expect(
            AnomalyFinder.findings(metrics: metrics(samples), today: Fixtures.today, calendar: Fixtures.utc).isEmpty)
    }
}

@Suite struct DailyCheckInTests {
    @Test func comparesRecentValuesWithTheirMedians() throws {
        var sleep = (1...28).map { Fixtures.sleep(wakeDay: Fixtures.daysAgo($0), hours: 7 + Double($0 % 3) * 0.25) }
        sleep.append(Fixtures.sleep(wakeDay: Fixtures.today, hours: 6.5))
        let samples = (1...20).map { Fixtures.quantity(.stepCount, day: Fixtures.daysAgo($0), value: 8_000) }

        let report = DailyCheckInBuilder.build(
            Fixtures.dataset(sleep: sleep, samples: samples),
            clock: Fixtures.clock,
            calendar: Fixtures.utc
        )

        #expect(report.kind == .daily)
        #expect(report.periodStart == Fixtures.today)
        let sleepFinding = try #require(report.findings.first { $0.id == "today.sleepDuration" })
        guard case .dayComparison(let comparison) = sleepFinding.detail else {
            Issue.record("Wrong kind")
            return
        }
        #expect(comparison.daysAgo == 0)
        #expect(comparison.value == 6.5 * 3600)
        #expect(comparison.baselineMedian == 7.25 * 3600)
        #expect(report.findings.contains { $0.id == "today.steps" })
    }

    @Test func emptyWithoutData() {
        let report = DailyCheckInBuilder.build(HealthDataset(), clock: Fixtures.clock, calendar: Fixtures.utc)
        #expect(report.findings.isEmpty)
    }
}
