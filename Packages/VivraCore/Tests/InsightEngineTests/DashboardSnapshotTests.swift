import Foundation
import Testing
import VivraModel

@testable import InsightEngine

@Suite struct DashboardSnapshotTests {
    private func build(
        sleep: [SleepInterval] = [],
        samples: [QuantitySample] = [],
        workouts: [Workout] = [],
        logs: [LogEntry] = []
    ) -> DashboardSnapshot {
        DashboardSnapshot.build(
            Fixtures.dataset(sleep: sleep, samples: samples, workouts: workouts, logs: logs),
            clock: Fixtures.clock,
            calendar: Fixtures.utc
        )
    }

    @Test func coversTheLastSevenDaysIncludingToday() {
        let snapshot = build()
        #expect(snapshot.days.first == Fixtures.daysAgo(6))
        #expect(snapshot.days.last == Fixtures.today)
        #expect(snapshot.days.count == 7)
        #expect(
            DashboardSnapshot.loadDays(clock: Fixtures.clock, calendar: Fixtures.utc) == (
                Fixtures.daysAgo(6), Fixtures.today
            ))
    }

    @Test func includesLastNightAndExcludesOlderNights() {
        let sleep = [
            Fixtures.sleep(wakeDay: Fixtures.today, hours: 7),
            Fixtures.sleep(wakeDay: Fixtures.daysAgo(7), hours: 6),
        ]
        #expect(build(sleep: sleep).sleep.map(\.day) == [Fixtures.today])
    }

    @Test func heartDaysNeedAValue() {
        let samples = [
            Fixtures.quantity(.restingHeartRate, day: Fixtures.daysAgo(1), value: 57),
            Fixtures.quantity(.heartRateVariabilitySDNN, day: Fixtures.daysAgo(1), value: 44),
            Fixtures.quantity(.heartRateVariabilitySDNN, day: Fixtures.daysAgo(3), value: 40),
        ]
        let heart = build(samples: samples).heart
        #expect(heart.map(\.day) == [Fixtures.daysAgo(3), Fixtures.daysAgo(1)])
        #expect(heart.last?.restingHeartRate == 57)
        #expect(heart.first?.restingHeartRate == nil)
    }

    @Test func workoutsAreNewestFirstAndKeepEverySource() {
        let older = Fixtures.workout(day: Fixtures.daysAgo(4), minutes: 30)
        let newer = Fixtures.workout(day: Fixtures.daysAgo(1), minutes: 30, source: Fixtures.strava)
        let outside = Fixtures.workout(day: Fixtures.daysAgo(10), minutes: 30)
        #expect(build(workouts: [older, outside, newer]).workouts == [newer, older])
    }

    @Test func activityTodayAndBodyValues() {
        let snapshot = build(
            samples: [
                Fixtures.quantity(.stepCount, day: Fixtures.daysAgo(2), value: 9_000, source: Fixtures.phone),
                Fixtures.quantity(.stepCount, day: Fixtures.daysAgo(2), value: 8_500),
                Fixtures.quantity(.bodyMass, day: Fixtures.daysAgo(5), value: 71.8),
                Fixtures.quantity(.bodyMass, day: Fixtures.daysAgo(2), value: 72.1),
            ],
            logs: [
                Fixtures.log(.drink, day: Fixtures.today, drink: .coffee, amount: 95),
                Fixtures.log(.drink, day: Fixtures.today, drink: .coffee, amount: 95),
                Fixtures.log(.mood, day: Fixtures.today, scale: 4),
                Fixtures.log(.drink, day: Fixtures.daysAgo(1), drink: .water, amount: 250),
            ]
        )
        #expect(snapshot.activity == [.init(day: Fixtures.daysAgo(2), steps: 9_000, exerciseMinutes: nil)])
        #expect(snapshot.todayIntake == [.caffeine: 190])
        #expect(snapshot.todayLogged == [.mood: 4])
        #expect(snapshot.latestBody[.weight] == .init(day: Fixtures.daysAgo(2), value: 72.1))
    }
}
