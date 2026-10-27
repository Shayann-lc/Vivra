import Foundation
import Testing
import VivraModel

@testable import InsightEngine

@Suite struct TodayGlanceTests {
    @Test func showsLatestValuesNextToTheUsual() throws {
        var sleep = (1...28).map { Fixtures.sleep(wakeDay: Fixtures.daysAgo($0), hours: 7 + Double($0 % 3) * 0.25) }
        sleep.append(Fixtures.sleep(wakeDay: Fixtures.today, hours: 6))
        let samples =
            (1...10).map { Fixtures.quantity(.restingHeartRate, day: Fixtures.daysAgo($0), value: 58) }
            + [Fixtures.quantity(.stepCount, day: Fixtures.today, value: 3_200)]
            + (1...10).map { Fixtures.quantity(.stepCount, day: Fixtures.daysAgo($0), value: 9_000) }

        let glance = TodayGlance.build(
            Fixtures.dataset(sleep: sleep, samples: samples),
            clock: Fixtures.clock,
            calendar: Fixtures.utc
        )

        let sleepRow = try #require(glance.rows.first { $0.metric == .sleepDuration })
        #expect(sleepRow.daysAgo == 0)
        #expect(sleepRow.value == 6 * 3600)
        #expect(sleepRow.usual == 7.25 * 3600)
        #expect(sleepRow.baselineDays == 28)
        let resting = try #require(glance.rows.first { $0.metric == .restingHeartRate })
        #expect(resting.daysAgo == 1)
        #expect(resting.usual == 58)
        let steps = try #require(glance.rows.first { $0.metric == .steps })
        #expect(steps.isSoFar)
        #expect(steps.usual == nil)
        #expect(glance.rows.map(\.metric) == [.sleepDuration, .restingHeartRate, .steps])
    }

    @Test func noUsualWithoutAWeekOfHistory() throws {
        let samples = (0...3).map { Fixtures.quantity(.heartRateVariabilitySDNN, day: Fixtures.daysAgo($0), value: 40) }
        let glance = TodayGlance.build(
            Fixtures.dataset(samples: samples), clock: Fixtures.clock, calendar: Fixtures.utc)
        let row = try #require(glance.rows.first)
        #expect(row.usual == nil)
        #expect(row.baselineDays == 3)
    }

    @Test func worthNoticingPrefersAnAnomaly() {
        var samples = (1...28).map {
            Fixtures.quantity(.restingHeartRate, day: Fixtures.daysAgo($0), value: 57 + Double($0 % 5))
        }
        samples.append(Fixtures.quantity(.restingHeartRate, day: Fixtures.today, value: 75))
        let glance = TodayGlance.build(
            Fixtures.dataset(samples: samples), clock: Fixtures.clock, calendar: Fixtures.utc)
        #expect(glance.worthNoticing?.id == "anomaly.restingHeartRate")
    }

    @Test func historyHasAUsualBandFromCompleteDays() {
        let samples =
            (1...20).map { Fixtures.quantity(.stepCount, day: Fixtures.daysAgo($0), value: Double(5_000 + $0 * 100)) }
            + [Fixtures.quantity(.stepCount, day: Fixtures.today, value: 100)]
        let history = MetricHistory.build(
            .steps,
            dataset: Fixtures.dataset(samples: samples),
            clock: Fixtures.clock,
            calendar: Fixtures.utc
        )
        #expect(history.points.count == 21)
        #expect(history.points.last?.day == Fixtures.today)
        #expect(history.completeDays == 20)
        #expect(history.median == 6_050)
        #expect(history.usualLow! < history.median! && history.median! < history.usualHigh!)
    }
}
