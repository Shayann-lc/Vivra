import Foundation
import InsightEngine
import NarrativeCore
import SyncCore
import Testing
import VivraModel

@testable import VivraStore

private let watch = SourceInfo(bundleIdentifier: "com.apple.health.watch", name: "Watch")
private let base = Date(timeIntervalSince1970: 1_775_000_000.123_456)

private func makeRepository() throws -> (HealthRepository, URL) {
    let directory = try makeTemporaryDirectory()
    let database = try VivraDatabase.open(in: directory, keyProvider: StaticKeyProvider(key: makeKey(9)))
    return (HealthRepository(database: database), directory)
}

private func sample(_ kind: QuantityKind = .restingHeartRate, offset: TimeInterval, value: Double = 60)
    -> QuantitySample
{
    let start = base.addingTimeInterval(offset)
    return QuantitySample(id: UUID(), kind: kind, start: start, end: start, value: value, source: watch)
}

@Suite struct HealthRepositoryTests {
    @Test func applyStoresObjectsAndAnchorTogether() async throws {
        let (repository, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        let samples = [sample(offset: 0), sample(offset: 60)]

        try await repository.apply(
            ChangeBatch(quantitySamples: samples, newAnchor: Data([1]), hasMore: false), for: .restingHeartRate)

        #expect(try await repository.anchor(for: .restingHeartRate) == Data([1]))
        #expect(try await repository.anchor(for: .sleep) == nil)
        let stored = try await repository.quantitySamples(
            [.restingHeartRate], from: base, to: base.addingTimeInterval(120))
        #expect(stored == samples)
    }

    @Test func reapplyingABatchDoesNotDuplicate() async throws {
        let (repository, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        let batch = ChangeBatch(quantitySamples: [sample(offset: 0)], newAnchor: Data([1]), hasMore: false)

        try await repository.apply(batch, for: .restingHeartRate)
        try await repository.apply(batch, for: .restingHeartRate)

        let stored = try await repository.quantitySamples(
            [.restingHeartRate], from: base, to: base.addingTimeInterval(1))
        #expect(stored.count == 1)
    }

    @Test func deletionsRemoveFromTheRightTable() async throws {
        let (repository, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workout = Workout(
            id: UUID(),
            activityType: 37,
            start: base,
            end: base.addingTimeInterval(1800),
            duration: 1800,
            activeEnergyKilocalories: 250,
            distanceMeters: 5000,
            source: watch
        )
        let interval = SleepInterval(
            id: UUID(), stage: .deep, start: base, end: base.addingTimeInterval(3600), source: watch)
        try await repository.apply(
            ChangeBatch(workouts: [workout], newAnchor: Data([1]), hasMore: false), for: .workouts)
        try await repository.apply(
            ChangeBatch(sleepIntervals: [interval], newAnchor: Data([1]), hasMore: false), for: .sleep)
        #expect(try await repository.workouts(from: base, to: base.addingTimeInterval(1)) == [workout])

        try await repository.apply(
            ChangeBatch(deletedIDs: [workout.id], newAnchor: Data([2]), hasMore: false), for: .workouts)

        #expect(try await repository.workouts(from: base, to: base.addingTimeInterval(1)).isEmpty)
        #expect(try await repository.sleepIntervals(endingFrom: base, to: base.addingTimeInterval(7200)) == [interval])
        #expect(try await repository.anchor(for: .workouts) == Data([2]))
    }

    @Test func readsFilterByKindAndRange() async throws {
        let (repository, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inside = sample(offset: 10)
        let batch = ChangeBatch(
            quantitySamples: [inside, sample(offset: -10), sample(offset: 100), sample(.heartRate, offset: 10)],
            newAnchor: Data([1]),
            hasMore: false
        )
        try await repository.apply(batch, for: .restingHeartRate)

        let stored = try await repository.quantitySamples(
            [.restingHeartRate], from: base, to: base.addingTimeInterval(100))
        #expect(stored == [inside])
    }

    @Test func reportsRoundTrip() async throws {
        let (repository, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        let finding = Finding(
            id: "weekly.restingHeartRate",
            detail: .weeklyAverage(
                WeeklyAverage(
                    metric: .restingHeartRate, thisWeek: 58, thisWeekDays: 7, previousWeek: nil, previousWeekDays: 0)
            )
        )
        let report = WeeklyReport(
            periodStart: Day(year: 2026, month: 3, day: 25),
            periodEnd: Day(year: 2026, month: 3, day: 31),
            findings: [finding]
        )
        let summary = await SummaryComposer.compose(report, narrator: nil)
        let stored = StoredReport(
            periodStart: report.periodStart, periodEnd: report.periodEnd, createdAt: base, summary: summary)

        #expect(try await repository.latestReport() == nil)
        try await repository.saveReport(stored)

        #expect(try await repository.latestReport() == stored)
    }
}
