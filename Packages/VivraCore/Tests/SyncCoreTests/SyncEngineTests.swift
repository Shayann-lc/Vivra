import Foundation
import Testing
import VivraModel

@testable import SyncCore

private let source = SourceInfo(bundleIdentifier: "com.apple.health.watch", name: "Watch")
private let utc = DayCalendar(timeZone: TimeZone(identifier: "UTC")!)
/// 2026-03-15 10:00 UTC
private let now = Date(timeIntervalSince1970: 1_773_568_800)

private func sample(_ minutesAgo: Double, value: Double = 60) -> QuantitySample {
    let start = now.addingTimeInterval(-minutesAgo * 60)
    return QuantitySample(id: UUID(), kind: .restingHeartRate, start: start, end: start, value: value, source: source)
}

/// An append-only change log per type; the anchor is the log position.
private actor FakeHealthDataSource: HealthDataSource {
    enum Event {
        case add(QuantitySample)
        case delete(UUID)
    }

    private var log: [HealthDataType: [Event]] = [:]
    private(set) var requests: [(type: HealthDataType, anchor: Int?, earliestStart: Date)] = []
    var failingTypes: Set<HealthDataType> = []

    func append(_ events: [Event], to type: HealthDataType) {
        log[type, default: []].append(contentsOf: events)
    }

    func failTypes(_ types: Set<HealthDataType>) {
        failingTypes = types
    }

    func changes(for type: HealthDataType, since anchor: Data?, earliestStart: Date, limit: Int) async throws
        -> ChangeBatch
    {
        let position = anchor.map { Int(String(decoding: $0, as: UTF8.self))! }
        requests.append((type, position, earliestStart))
        if failingTypes.contains(type) { throw NSError(domain: "fake", code: 42) }

        let events = log[type, default: []]
        let from = position ?? 0
        let to = min(events.count, from + limit)
        var batch = ChangeBatch(newAnchor: Data(String(to).utf8), hasMore: to - from == limit)
        for event in events[from..<to] {
            switch event {
            case .add(let sample) where sample.start >= earliestStart:
                batch.quantitySamples.append(sample)
            case .add:
                break
            case .delete(let id):
                batch.deletedIDs.append(id)
            }
        }
        return batch
    }
}

private actor FakeSyncStore: SyncStore {
    private(set) var samples: [UUID: QuantitySample] = [:]
    private(set) var anchors: [HealthDataType: Data] = [:]
    private var succeedBeforeFailing: Int?

    /// Lets `successes` applies through, then fails the next one.
    func failApply(afterSucceeding successes: Int = 0) {
        succeedBeforeFailing = successes
    }

    func anchor(for type: HealthDataType) async throws -> Data? {
        anchors[type]
    }

    func apply(_ batch: ChangeBatch, for type: HealthDataType) async throws {
        if let remaining = succeedBeforeFailing {
            if remaining == 0 {
                succeedBeforeFailing = nil
                throw NSError(domain: "fake-store", code: 7)
            }
            succeedBeforeFailing = remaining - 1
        }
        for sample in batch.quantitySamples { samples[sample.id] = sample }
        for id in batch.deletedIDs { samples[id] = nil }
        anchors[type] = batch.newAnchor
    }
}

@Suite struct SyncEngineTests {
    private func makeEngine(_ source: FakeHealthDataSource, _ store: FakeSyncStore, batchLimit: Int = 2) -> SyncEngine {
        SyncEngine(source: source, store: store, clock: FixedClock(now), calendar: utc, batchLimit: batchLimit)
    }

    @Test func initialSyncPagesThroughEverything() async throws {
        let health = FakeHealthDataSource()
        let store = FakeSyncStore()
        await health.append((1...5).map { .add(sample(Double($0))) }, to: .restingHeartRate)

        let summary = try await makeEngine(health, store).sync(.restingHeartRate)

        #expect(summary.added == 5)
        #expect(summary.batches == 3)
        #expect(await store.samples.count == 5)
        #expect(await store.anchors[.restingHeartRate] == Data("5".utf8))
    }

    @Test func incrementalSyncFetchesOnlyNewChanges() async throws {
        let health = FakeHealthDataSource()
        let store = FakeSyncStore()
        let engine = makeEngine(health, store, batchLimit: 10)
        await health.append([.add(sample(1)), .add(sample(2))], to: .restingHeartRate)
        _ = try await engine.sync(.restingHeartRate)

        await health.append([.add(sample(3))], to: .restingHeartRate)
        let summary = try await engine.sync(.restingHeartRate)

        #expect(summary.added == 1)
        #expect(await health.requests.last?.anchor == 2)
        #expect(await store.samples.count == 3)
    }

    @Test func deletionsAreApplied() async throws {
        let health = FakeHealthDataSource()
        let store = FakeSyncStore()
        let engine = makeEngine(health, store)
        let doomed = sample(1)
        await health.append([.add(doomed), .add(sample(2))], to: .restingHeartRate)
        _ = try await engine.sync(.restingHeartRate)

        await health.append([.delete(doomed.id)], to: .restingHeartRate)
        let summary = try await engine.sync(.restingHeartRate)

        #expect(summary.deleted == 1)
        #expect(await store.samples[doomed.id] == nil)
        #expect(await store.samples.count == 1)
    }

    /// Simulates a crash between fetch and commit: the anchor must not
    /// advance, and the retry must neither lose nor duplicate objects.
    @Test func failedCommitIsRetriedWithoutDuplicates() async throws {
        let health = FakeHealthDataSource()
        let store = FakeSyncStore()
        let engine = makeEngine(health, store)
        await health.append((1...4).map { .add(sample(Double($0))) }, to: .restingHeartRate)

        await store.failApply()
        await #expect(throws: (any Error).self) { try await engine.sync(.restingHeartRate) }
        #expect(await store.anchors[.restingHeartRate] == nil)

        let summary = try await engine.sync(.restingHeartRate)
        #expect(summary.added == 4)
        #expect(await store.samples.count == 4)
    }

    @Test func failureMidwayKeepsCommittedPages() async throws {
        let health = FakeHealthDataSource()
        let store = FakeSyncStore()
        let engine = makeEngine(health, store)
        await health.append((1...6).map { .add(sample(Double($0))) }, to: .restingHeartRate)

        // Pages of 2: the first two commit, the third fails.
        await store.failApply(afterSucceeding: 2)
        await #expect(throws: (any Error).self) { try await engine.sync(.restingHeartRate) }
        #expect(await store.anchors[.restingHeartRate] == Data("4".utf8))
        #expect(await store.samples.count == 4)

        let summary = try await engine.sync(.restingHeartRate)
        #expect(summary.added == 2)
        #expect(await store.samples.count == 6)
    }

    @Test func requestsNinetyDaysOfHistoryFromMidnight() async throws {
        let health = FakeHealthDataSource()
        let store = FakeSyncStore()
        _ = try await makeEngine(health, store).sync(.restingHeartRate)

        // 2026-03-15 minus 90 days = 2025-12-15, 00:00 UTC.
        let expected = utc.start(of: Day(year: 2025, month: 12, day: 15))
        #expect(await health.requests.first?.earliestStart == expected)
    }

    @Test func oneFailingTypeDoesNotStopOthers() async {
        let health = FakeHealthDataSource()
        let store = FakeSyncStore()
        await health.append([.add(sample(1))], to: .restingHeartRate)
        await health.failTypes([.sleep])

        let report = await makeEngine(health, store).sync([.sleep, .restingHeartRate])

        #expect(report.failures == [SyncFailure(type: .sleep, code: 42)])
        #expect(report.summaries[.restingHeartRate]?.added == 1)
    }

    @Test func stopsWhenSourceRepeatsAnchor() async throws {
        struct StuckSource: HealthDataSource {
            func changes(for type: HealthDataType, since anchor: Data?, earliestStart: Date, limit: Int) async throws
                -> ChangeBatch
            {
                ChangeBatch(newAnchor: Data("same".utf8), hasMore: true)
            }
        }
        let engine = SyncEngine(source: StuckSource(), store: FakeSyncStore(), clock: FixedClock(now), calendar: utc)

        let summary = try await engine.sync(.sleep)

        #expect(summary.batches == 2)
    }
}

@Suite struct PermissionGroupTests {
    @Test func groupsCoverEveryTypeExactlyOnce() {
        let grouped = PermissionGroup.allCases.flatMap(\.dataTypes)
        #expect(grouped.count == HealthDataType.allCases.count)
        #expect(Set(grouped) == Set(HealthDataType.allCases))
    }

    @Test func phaseOneUsersAreAskedForNewAndExpandedGroups() {
        let pending = PermissionGroup.pending(requested: PermissionGroup.phaseOneRevisions)
        #expect(pending == [.heart, .activity, .mind, .nutrition, .body])
        let everything = Dictionary(uniqueKeysWithValues: PermissionGroup.allCases.map { ($0, $0.revision) })
        #expect(PermissionGroup.pending(requested: everything).isEmpty)
    }

    @Test func typeNamesLineUpWithKinds() {
        for kind in QuantityKind.allCases { #expect(HealthDataType(kind).quantityKind == kind) }
        for kind in CategoryKind.allCases { #expect(HealthDataType(kind).categoryKind == kind) }
        #expect(HealthDataType.sleep.quantityKind == nil)
    }
}

@Suite struct HealthWriteTests {
    private let now = Date(timeIntervalSince1970: 1_775_000_000)

    @Test func moodMapsOntoValence() {
        #expect(HealthWrite.for(LogEntry(kind: .mood, timestamp: now, scale: 1)) == .stateOfMind(valence: -1))
        #expect(HealthWrite.for(LogEntry(kind: .mood, timestamp: now, scale: 3)) == .stateOfMind(valence: 0))
        #expect(HealthWrite.for(LogEntry(kind: .mood, timestamp: now, scale: 5)) == .stateOfMind(valence: 1))
        #expect(HealthWrite.for(LogEntry(kind: .mood, timestamp: now, scale: 9)) == nil)
    }

    @Test func drinksMapToIntakeTypes() {
        let coffee = LogEntry(kind: .drink, timestamp: now, drink: .coffee, amount: 95)
        #expect(HealthWrite.for(coffee) == .quantity(.dietaryCaffeine, value: 95))
        #expect(HealthWrite.for(coffee)?.dataType == .dietaryCaffeine)
        let beer = LogEntry(kind: .drink, timestamp: now, drink: .alcohol, amount: 1)
        #expect(HealthWrite.for(beer) == .quantity(.numberOfAlcoholicBeverages, value: 1))
    }

    @Test func entriesWithoutAHealthEquivalentStayLocal() {
        #expect(HealthWrite.for(LogEntry(kind: .stress, timestamp: now, scale: 2)) == nil)
        #expect(HealthWrite.for(LogEntry(kind: .note, timestamp: now, note: "slept badly")) == nil)
        #expect(HealthWrite.for(LogEntry(kind: .meal, timestamp: now)) == nil)
    }

    @Test func everyWrittenTypeIsAlsoRead() {
        let read = Set(PermissionGroup.allCases.flatMap(\.dataTypes))
        #expect(Set(HealthWrite.writableTypes).isSubset(of: read))
    }
}
