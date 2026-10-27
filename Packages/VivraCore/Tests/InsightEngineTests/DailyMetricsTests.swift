import Foundation
import Testing
import VivraModel

@testable import InsightEngine

@Suite struct DailyMetricsTests {
    private let day = Fixtures.daysAgo(1)

    private func build(_ dataset: HealthDataset) -> DailyMetrics {
        DailyMetrics.build(dataset, calendar: Fixtures.utc, sourcePolicy: Fixtures.ownPolicy)
    }

    @Test func activityTotalsUseTheLargestSourceNotTheSum() {
        let metrics = build(
            Fixtures.dataset(samples: [
                Fixtures.quantity(.stepCount, day: day, value: 5_000, source: Fixtures.phone),
                Fixtures.quantity(.stepCount, day: day, value: 3_000, source: Fixtures.phone),
                Fixtures.quantity(.stepCount, day: day, value: 6_500, source: Fixtures.watch),
            ])
        )
        #expect(metrics.value(.steps, on: day) == 8_000)
    }

    @Test func intakeAddsSourcesAndLogsButIgnoresVivrasOwnSamples() {
        let otherApp = SourceInfo(bundleIdentifier: "com.example.waterapp", name: "Water")
        let metrics = build(
            Fixtures.dataset(
                samples: [
                    Fixtures.quantity(.dietaryWater, day: day, value: 500, source: otherApp),
                    Fixtures.quantity(.dietaryWater, day: day, value: 250, source: Fixtures.vivra),
                ],
                logs: [Fixtures.log(.drink, day: day, drink: .water, amount: 250)]
            )
        )
        #expect(metrics.value(.water, on: day) == 750)
    }

    @Test func moodCombinesLogsWithOtherAppsStateOfMind() {
        func state(_ valence: Double, _ source: SourceInfo) -> StateOfMindSample {
            StateOfMindSample(
                id: UUID(),
                date: Fixtures.date(day, hour: 9),
                kind: .momentaryEmotion,
                valence: valence,
                labels: [],
                associations: [],
                source: source
            )
        }
        let metrics = build(
            Fixtures.dataset(
                statesOfMind: [state(0.5, Fixtures.phone), state(-1, Fixtures.vivra)],
                logs: [Fixtures.log(.mood, day: day, scale: 3), Fixtures.log(.stress, day: day, scale: 2)]
            )
        )
        #expect(metrics.value(.mood, on: day) == 3.5)
        #expect(metrics.value(.stressLevel, on: day) == 2)
    }

    @Test func loggedWhenConsumedMetricsReadZeroBetweenRecords() {
        let first = Fixtures.daysAgo(5)
        let last = Fixtures.daysAgo(2)
        let metrics = build(
            Fixtures.dataset(logs: [
                Fixtures.log(.drink, day: first, drink: .alcohol, amount: 2),
                Fixtures.log(.drink, day: last, drink: .alcohol, amount: 1),
            ])
        )
        #expect(metrics.value(.alcohol, on: first) == 2)
        #expect(metrics.value(.alcohol, on: Fixtures.daysAgo(3)) == 0)
        #expect(metrics.value(.alcohol, on: Fixtures.daysAgo(6)) == nil)
        #expect(metrics.value(.alcohol, on: Fixtures.daysAgo(1)) == nil)
        // Not a logged-when-consumed metric.
        #expect(metrics.value(.mood, on: first) == nil)
    }

    @Test func categoryEventsBecomeStandHoursAndMindfulMinutes() {
        func event(_ kind: CategoryKind, hour: Double, minutes: Double, value: Int) -> CategoryEvent {
            let start = Fixtures.date(day, hour: hour)
            return CategoryEvent(
                id: UUID(),
                kind: kind,
                start: start,
                end: start.addingTimeInterval(minutes * 60),
                value: value,
                source: Fixtures.watch
            )
        }
        let metrics = build(
            Fixtures.dataset(events: [
                event(.standHour, hour: 9, minutes: 60, value: 0),
                event(.standHour, hour: 10, minutes: 60, value: 1),
                event(.standHour, hour: 11, minutes: 60, value: 0),
                event(.mindfulSession, hour: 7, minutes: 10, value: 0),
                event(.mindfulSession, hour: 21, minutes: 5, value: 0),
                event(.irregularRhythm, hour: 3, minutes: 1, value: 0),
            ])
        )
        #expect(metrics.value(.standHours, on: day) == 2)
        #expect(metrics.value(.mindfulMinutes, on: day) == 15)
    }

    @Test func totalsHelperAttributesSamplesToTheirStartDay() {
        let totals = DailySourceTotals.totals(
            from: [
                Fixtures.quantity(.stepCount, day: day, value: 100),
                Fixtures.quantity(.stepCount, day: day, value: 50),
                Fixtures.quantity(.restingHeartRate, day: day, value: 60),
            ],
            calendar: Fixtures.utc
        )
        #expect(totals == [.stepCount: [day: ["com.apple.health.watch": 150]]])
    }
}
