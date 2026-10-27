import Foundation
import InsightEngine
import SyncCore
import Testing
import VivraModel

@testable import VivraStore

private let watch = SourceInfo(bundleIdentifier: "com.apple.health.watch", name: "Watch")
private let phone = SourceInfo(bundleIdentifier: "com.apple.health.phone", name: "iPhone")
/// London switches to summer time on 2026-03-29, so that day is 23 hours long.
private let london = DayCalendar(timeZone: TimeZone(identifier: "Europe/London")!)

private func makeRepository() throws -> (HealthRepository, URL) {
    let directory = try makeTemporaryDirectory()
    let database = try VivraDatabase.open(in: directory, keyProvider: StaticKeyProvider(key: makeKey(11)))
    return (HealthRepository(database: database), directory)
}

private func at(_ day: Day, hour: Double) -> Date {
    london.start(of: day).addingTimeInterval(hour * 3600)
}

@Suite struct PhaseTwoRepositoryTests {
    @Test func sqlTotalsMatchTheEnginesReferenceAcrossDaylightSaving() async throws {
        let (repository, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        let days = [
            Day(year: 2026, month: 3, day: 28), Day(year: 2026, month: 3, day: 29), Day(year: 2026, month: 3, day: 30),
        ]
        var samples: [QuantitySample] = []
        for (index, day) in days.enumerated() {
            for hour in [0.25, 12, 22.5] {
                for source in [watch, phone] {
                    let start = at(day, hour: hour)
                    samples.append(
                        QuantitySample(
                            id: UUID(),
                            kind: .stepCount,
                            start: start,
                            end: start.addingTimeInterval(60),
                            value: Double(100 * (index + 1)),
                            source: source
                        )
                    )
                }
            }
        }
        // An average kind that must not be summed.
        samples.append(
            QuantitySample(
                id: UUID(), kind: .restingHeartRate, start: at(days[1], hour: 8), end: at(days[1], hour: 8), value: 60,
                source: watch)
        )
        try await repository.apply(
            ChangeBatch(quantitySamples: samples, newAnchor: Data([1]), hasMore: false), for: .stepCount)

        let fromSQL = try await repository.dailySourceTotals([.stepCount], days: days, calendar: london)

        #expect(fromSQL == DailySourceTotals.totals(from: samples, calendar: london))
        #expect(fromSQL[.stepCount]?[days[1]]?["com.apple.health.watch"] == 600)
    }

    @Test func newObjectTypesRoundTripAndDeleteFromTheirOwnTables() async throws {
        let (repository, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        let day = Day(year: 2026, month: 4, day: 2)
        let mindful = CategoryEvent(
            id: UUID(), kind: .mindfulSession, start: at(day, hour: 7), end: at(day, hour: 7.25), value: 0,
            source: watch)
        let state = StateOfMindSample(
            id: UUID(),
            date: at(day, hour: 9),
            kind: .dailyMood,
            valence: 0.4,
            labels: [3, 7],
            associations: [1],
            source: phone
        )
        let ecg = ECGRecord(id: UUID(), date: at(day, hour: 10), classification: .sinusRhythm, source: watch)
        try await repository.apply(
            ChangeBatch(categoryEvents: [mindful], newAnchor: Data([1]), hasMore: false), for: .mindfulSession)
        try await repository.apply(
            ChangeBatch(statesOfMind: [state], newAnchor: Data([1]), hasMore: false), for: .stateOfMind)
        try await repository.apply(
            ChangeBatch(ecgRecords: [ecg], newAnchor: Data([1]), hasMore: false), for: .electrocardiogram)

        let range = (from: london.start(of: day), to: london.start(of: london.adding(days: 1, to: day)))
        #expect(try await repository.categoryEvents([.mindfulSession], from: range.from, to: range.to) == [mindful])
        #expect(try await repository.statesOfMind(from: range.from, to: range.to) == [state])
        #expect(try await repository.ecgRecords(from: range.from, to: range.to) == [ecg])

        try await repository.apply(
            ChangeBatch(deletedIDs: [state.id], newAnchor: Data([2]), hasMore: false), for: .stateOfMind)
        #expect(try await repository.statesOfMind(from: range.from, to: range.to).isEmpty)
        #expect(try await repository.categoryEvents([.mindfulSession], from: range.from, to: range.to) == [mindful])
    }

    @Test func logsSaveUpdateAndDelete() async throws {
        let (repository, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        let day = Day(year: 2026, month: 4, day: 2)
        let mood = LogEntry(kind: .mood, timestamp: at(day, hour: 9), scale: 4)
        let coffee = LogEntry(
            kind: .drink, timestamp: at(day, hour: 10), drink: .coffee, amount: 95, note: "flat white")
        try await repository.saveLog(mood)
        try await repository.saveLog(coffee)
        let range = (from: london.start(of: day), to: london.start(of: london.adding(days: 1, to: day)))
        #expect(try await repository.logs(from: range.from, to: range.to) == [coffee, mood])

        let written = coffee.with(healthKitSampleID: UUID())
        try await repository.saveLog(written)
        #expect(try await repository.logs(from: range.from, to: range.to).first == written)

        try await repository.deleteLog(id: mood.id)
        #expect(try await repository.logs(from: range.from, to: range.to) == [written])
    }

    @Test func datasetGathersEverythingForTheRange() async throws {
        let (repository, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        let day = Day(year: 2026, month: 4, day: 2)
        let steps = QuantitySample(
            id: UUID(), kind: .stepCount, start: at(day, hour: 12), end: at(day, hour: 13), value: 4_000, source: phone)
        let resting = QuantitySample(
            id: UUID(), kind: .restingHeartRate, start: at(day, hour: 8), end: at(day, hour: 8), value: 58,
            source: watch)
        let night = SleepInterval(
            id: UUID(), stage: .core, start: at(day, hour: -1), end: at(day, hour: 6), source: watch)
        try await repository.apply(
            ChangeBatch(quantitySamples: [steps, resting], newAnchor: Data([1]), hasMore: false), for: .stepCount)
        try await repository.apply(
            ChangeBatch(sleepIntervals: [night], newAnchor: Data([1]), hasMore: false), for: .sleep)
        try await repository.saveLog(LogEntry(kind: .stress, timestamp: at(day, hour: 15), scale: 2))

        let dataset = try await repository.dataset(first: day, last: day, calendar: london)

        #expect(dataset.samples == [resting])
        #expect(dataset.dailySourceTotals[.stepCount]?[day]?["com.apple.health.phone"] == 4_000)
        #expect(dataset.sleepIntervals == [night])
        #expect(dataset.logs.count == 1)
    }
}
