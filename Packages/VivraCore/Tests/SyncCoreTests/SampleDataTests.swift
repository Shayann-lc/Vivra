import Foundation
import Testing
import VivraModel

@testable import SyncCore

@Suite struct SampleDataTests {
    private let calendar = DayCalendar(timeZone: TimeZone(identifier: "Europe/London")!)
    /// Tuesday 27 October 2026, 14:00 in London.
    private let now = Date(timeIntervalSince1970: 1_793_109_600)

    @Test func isDeterministic() {
        let first = SampleData.generate(now: now, calendar: calendar)
        let second = SampleData.generate(now: now, calendar: calendar)
        #expect(first.logs == second.logs)
        #expect(first.batches.map(\.batch) == second.batches.map(\.batch))
        #expect(first.batches.map(\.type) == second.batches.map(\.type))
    }

    @Test func nothingIsLaterThanNow() {
        let data = SampleData.generate(now: now, calendar: calendar)
        for (_, batch) in data.batches {
            #expect(batch.quantitySamples.allSatisfy { $0.end <= now })
            #expect(batch.sleepIntervals.allSatisfy { $0.end <= now })
            #expect(batch.workouts.allSatisfy { $0.end <= now })
        }
        #expect(data.logs.allSatisfy { $0.timestamp <= now })
    }

    @Test func coversNinetyDaysWithPlausibleValues() throws {
        let data = SampleData.generate(now: now, calendar: calendar)
        let sleep = try #require(data.batches.first { $0.type == .sleep }?.batch.sleepIntervals)
        let nights = Set(sleep.map { morning(of: $0) })
        #expect(nights.count == 90)

        let resting = try #require(data.batches.first { $0.type == .restingHeartRate }?.batch.quantitySamples)
        #expect(resting.count == 90)
        #expect(resting.allSatisfy { (45...75).contains($0.value) })

        let steps = try #require(data.batches.first { $0.type == .stepCount }?.batch.quantitySamples)
        #expect(steps.allSatisfy { $0.value >= 0 && $0.value < 25_000 })
        #expect(data.batches.allSatisfy { $0.batch.quantitySamples.allSatisfy { $0.source == SampleData.source } })

        let moods = data.logs.filter { $0.kind == .mood }
        #expect(moods.count > 60)
        #expect(moods.allSatisfy { LogEntry.scaleRange.contains($0.scale ?? 0) })
        #expect(!(data.batches.first { $0.type == .workouts }?.batch.workouts.isEmpty ?? true))
    }

    /// Just after midnight, tonight's sleep is still in progress, so the
    /// latest night is the previous one rather than a partial night.
    @Test func leavesOutANightStillInProgress() throws {
        let justAfterMidnight = Date(timeIntervalSince1970: 1_793_061_000)  // 27 Oct 2026, 00:30 London
        let data = SampleData.generate(now: justAfterMidnight, calendar: calendar)
        let sleep = try #require(data.batches.first { $0.type == .sleep }?.batch.sleepIntervals)
        let byNight = Dictionary(grouping: sleep.filter(\.stage.isAsleep)) { morning(of: $0) }
        #expect(byNight.count == 89)
        for (_, intervals) in byNight {
            let hours = intervals.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 3600
            #expect(hours >= 4)
        }
    }

    @Test func eachNightAddsUpToItsAsleepTimeWithoutOverlaps() throws {
        let data = SampleData.generate(now: now, calendar: calendar)
        let sleep = try #require(data.batches.first { $0.type == .sleep }?.batch.sleepIntervals)
        let sorted = sleep.sorted { $0.start < $1.start }
        for (previous, next) in zip(sorted, sorted.dropFirst()) {
            #expect(previous.end <= next.start)
        }
        let byNight = Dictionary(grouping: sleep.filter(\.stage.isAsleep)) { morning(of: $0) }
        for (_, intervals) in byNight {
            let hours = intervals.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 3600
            #expect((4...10).contains(hours))
        }
    }

    /// The morning a night ends on, for intervals before or after midnight.
    private func morning(of interval: SleepInterval) -> Day {
        calendar.day(interval.end.addingTimeInterval(12 * 3600))
    }
}
