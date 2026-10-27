import Foundation
import VivraLogging
import VivraModel

/// A HealthKit data type Vivra syncs, as one anchored query each. Quantity
/// and category cases share their names with `QuantityKind` and
/// `CategoryKind`.
public enum HealthDataType: String, Codable, Sendable, CaseIterable {
    case sleep
    case workouts
    case stateOfMind
    case electrocardiogram
    // Categories
    case standHour
    case mindfulSession
    case irregularRhythm
    // Heart
    case heartRate
    case restingHeartRate
    case heartRateVariabilitySDNN
    case walkingHeartRateAverage
    case vo2Max
    // Activity
    case stepCount
    case activeEnergyBurned
    case basalEnergyBurned
    case appleExerciseTime
    case distanceWalkingRunning
    // Nutrition and hydration
    case dietaryEnergyConsumed
    case dietaryProtein
    case dietaryCarbohydrates
    case dietaryFatTotal
    case dietaryWater
    case dietaryCaffeine
    case numberOfAlcoholicBeverages
    // Body
    case bodyMass
    case bodyFatPercentage
    case respiratoryRate
    case oxygenSaturation
    case appleSleepingWristTemperature

    public var quantityKind: QuantityKind? { QuantityKind(rawValue: rawValue) }
    public var categoryKind: CategoryKind? { CategoryKind(rawValue: rawValue) }

    public init(_ kind: QuantityKind) { self.init(rawValue: kind.rawValue)! }
    public init(_ kind: CategoryKind) { self.init(rawValue: kind.rawValue)! }
}

/// One page of changes from an anchored query.
public struct ChangeBatch: Sendable, Equatable {
    public var quantitySamples: [QuantitySample]
    public var sleepIntervals: [SleepInterval]
    public var workouts: [Workout]
    public var categoryEvents: [CategoryEvent]
    public var statesOfMind: [StateOfMindSample]
    public var ecgRecords: [ECGRecord]
    /// HealthKit UUIDs of deleted objects of this type.
    public var deletedIDs: [UUID]
    /// Opaque, serialized `HKQueryAnchor`. Stored together with the batch.
    public var newAnchor: Data
    /// True when the page was full, so another page may follow.
    public var hasMore: Bool

    public init(
        quantitySamples: [QuantitySample] = [],
        sleepIntervals: [SleepInterval] = [],
        workouts: [Workout] = [],
        categoryEvents: [CategoryEvent] = [],
        statesOfMind: [StateOfMindSample] = [],
        ecgRecords: [ECGRecord] = [],
        deletedIDs: [UUID] = [],
        newAnchor: Data,
        hasMore: Bool
    ) {
        self.quantitySamples = quantitySamples
        self.sleepIntervals = sleepIntervals
        self.workouts = workouts
        self.categoryEvents = categoryEvents
        self.statesOfMind = statesOfMind
        self.ecgRecords = ecgRecords
        self.deletedIDs = deletedIDs
        self.newAnchor = newAnchor
        self.hasMore = hasMore
    }

    public var addedCount: Int {
        quantitySamples.count + sleepIntervals.count + workouts.count + categoryEvents.count + statesOfMind.count
            + ecgRecords.count
    }
}

/// Reads changes from Apple Health. The real implementation wraps
/// `HKAnchoredObjectQueryDescriptor`; tests use a fake.
public protocol HealthDataSource: Sendable {
    /// Returns changes after `anchor` (all objects starting on or after
    /// `earliestStart` when `anchor` is nil), at most `limit` objects.
    func changes(
        for type: HealthDataType,
        since anchor: Data?,
        earliestStart: Date,
        limit: Int
    ) async throws -> ChangeBatch
}

/// Persists synced objects and anchors.
public protocol SyncStore: Sendable {
    func anchor(for type: HealthDataType) async throws -> Data?
    /// Must upsert added objects, delete `deletedIDs` and save `newAnchor`
    /// in one transaction, so a crash can never leave an anchor ahead of
    /// the data it covers.
    func apply(_ batch: ChangeBatch, for type: HealthDataType) async throws
}

public struct TypeSyncSummary: Sendable, Equatable {
    public var added = 0
    public var deleted = 0
    public var batches = 0

    public init(added: Int = 0, deleted: Int = 0, batches: Int = 0) {
        self.added = added
        self.deleted = deleted
        self.batches = batches
    }
}

public struct SyncFailure: Error, Sendable, Equatable {
    public let type: HealthDataType
    /// The underlying `NSError` code. Descriptions are never kept: they can
    /// contain values.
    public let code: Int
}

public struct SyncReport: Sendable {
    public var summaries: [HealthDataType: TypeSyncSummary] = [:]
    public var failures: [SyncFailure] = []

    public var totalAdded: Int { summaries.values.reduce(0) { $0 + $1.added } }
    public var totalDeleted: Int { summaries.values.reduce(0) { $0 + $1.deleted } }
}

/// Incrementally syncs Apple Health into the local store.
///
/// An actor, so overlapping triggers (launch, pull-to-refresh, background
/// delivery) run one at a time instead of racing on anchors.
public actor SyncEngine {
    public static let defaultHistoryDays = 90
    public static let defaultBatchLimit = 2_000

    private let source: any HealthDataSource
    private let store: any SyncStore
    private let clock: any Clock
    private let calendar: DayCalendar
    private let historyDays: Int
    private let batchLimit: Int

    public init(
        source: any HealthDataSource,
        store: any SyncStore,
        clock: any Clock,
        calendar: DayCalendar,
        historyDays: Int = SyncEngine.defaultHistoryDays,
        batchLimit: Int = SyncEngine.defaultBatchLimit
    ) {
        self.source = source
        self.store = store
        self.clock = clock
        self.calendar = calendar
        self.historyDays = historyDays
        self.batchLimit = batchLimit
    }

    /// The earliest start date fetched: midnight, `historyDays` days ago.
    public var earliestStart: Date {
        let today = calendar.day(clock.now)
        return calendar.start(of: calendar.adding(days: -historyDays, to: today))
    }

    /// Syncs each type independently; a failure in one doesn't stop the rest.
    public func sync(_ types: [HealthDataType] = HealthDataType.allCases) async -> SyncReport {
        var report = SyncReport()
        for type in types {
            do {
                report.summaries[type] = try await sync(type)
            } catch {
                let failure = SyncFailure(type: type, code: (error as NSError).code)
                Log.sync.failure("Type sync failed", code: failure.code)
                report.failures.append(failure)
            }
        }
        Log.sync.event("Sync finished, objects added", count: report.totalAdded)
        return report
    }

    public func sync(_ type: HealthDataType) async throws -> TypeSyncSummary {
        var summary = TypeSyncSummary()
        var anchor = try await store.anchor(for: type)
        let earliestStart = earliestStart

        while true {
            let batch = try await source.changes(
                for: type,
                since: anchor,
                earliestStart: earliestStart,
                limit: batchLimit
            )
            try await store.apply(batch, for: type)
            summary.batches += 1
            summary.added += batch.addedCount
            summary.deleted += batch.deletedIDs.count

            // Stop on a short page, or if the source returns the same anchor
            // (a misbehaving source must not spin forever).
            guard batch.hasMore, batch.newAnchor != anchor else { break }
            anchor = batch.newAnchor
        }
        return summary
    }
}
