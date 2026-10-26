import Foundation
import Testing
import VivraModel

@testable import InsightEngine

@Suite struct SleepNightTests {
    private let calendar = Fixtures.utc
    private let day = Fixtures.today

    private func interval(_ start: Double, _ end: Double, _ stage: SleepStage, source: SourceInfo = Fixtures.watch)
        -> SleepInterval
    {
        SleepInterval(
            id: UUID(),
            stage: stage,
            start: Fixtures.date(day, hour: start),
            end: Fixtures.date(day, hour: end),
            source: source
        )
    }

    @Test func nightStartingBeforeMidnightBelongsToWakeDay() {
        let previous = calendar.adding(days: -1, to: day)
        let intervals = [
            SleepInterval(
                id: UUID(),
                stage: .core,
                start: Fixtures.date(previous, hour: 23),
                end: Fixtures.date(day, hour: 6.5),
                source: Fixtures.watch
            )
        ]
        let nights = SleepNightBuilder.nights(from: intervals, calendar: calendar)
        #expect(nights.map(\.wakeDay) == [day])
        #expect(nights.first?.asleep == 7.5 * 3600)
    }

    @Test func dayBoundaryIsSixPM() {
        #expect(SleepNightBuilder.wakeDay(for: Fixtures.date(day, hour: 17.99), calendar: calendar) == day)
        #expect(
            SleepNightBuilder.wakeDay(for: Fixtures.date(day, hour: 18), calendar: calendar)
                == calendar.adding(days: 1, to: day)
        )
    }

    @Test func overlappingIntervalsAreMergedAndStagesSummed() {
        let intervals = [
            interval(0, 1, .core),
            interval(1, 2, .deep),
            interval(1.5, 2.5, .rem),  // overlaps deep by 30 min
            interval(2.5, 3, .awake),
            interval(0, 3, .inBed),
        ]
        let night = SleepNightBuilder.nights(from: intervals, calendar: calendar).first!
        #expect(night.asleep == 2.5 * 3600)
        #expect(night.stages[.deep] == 3600)
        #expect(night.stages[.awake] == 1800)
        #expect(night.inBed == 10_800)
    }

    @Test func stagedSourceWinsOverLongerUnstagedSource() {
        let intervals = [
            interval(0, 8, .asleepUnspecified, source: Fixtures.phone),
            interval(1, 7, .core, source: Fixtures.watch),
        ]
        let night = SleepNightBuilder.nights(from: intervals, calendar: calendar).first!
        #expect(night.source == Fixtures.watch)
        #expect(night.asleep == 6 * 3600)
    }

    @Test func inBedOnlyIsNotANight() {
        #expect(SleepNightBuilder.nights(from: [interval(0, 8, .inBed)], calendar: calendar).isEmpty)
    }
}
