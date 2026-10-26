import Foundation
import Testing
import VivraModel

@testable import InsightEngine

@Suite struct DashboardSnapshotTests {
    private func build(sleep: [SleepInterval] = [], samples: [QuantitySample] = [], workouts: [Workout] = [])
        -> DashboardSnapshot
    {
        DashboardSnapshot.build(
            sleepIntervals: sleep,
            samples: samples,
            workouts: workouts,
            clock: FixedClock(Fixtures.now),
            calendar: Fixtures.utc
        )
    }

    @Test func coversTheLastSevenDaysIncludingToday() {
        let snapshot = build()
        #expect(snapshot.days.first == Fixtures.daysAgo(6))
        #expect(snapshot.days.last == Fixtures.today)
        #expect(snapshot.days.count == 7)
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

    @Test func loadRangeStartsADayEarlyForSleep() {
        let range = DashboardSnapshot.loadRange(clock: FixedClock(Fixtures.now), calendar: Fixtures.utc)
        #expect(range.start == Fixtures.utc.start(of: Fixtures.daysAgo(7)))
        #expect(range.end == Fixtures.utc.start(of: Fixtures.utc.adding(days: 1, to: Fixtures.today)))
    }
}
