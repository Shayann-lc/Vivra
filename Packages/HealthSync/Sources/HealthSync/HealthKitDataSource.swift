import Foundation
import HealthKit
import SyncCore
import VivraLogging
import VivraModel

/// Reads Apple Health through anchored queries, and wakes Vivra on changes
/// through observer queries with background delivery.
///
/// `@unchecked Sendable`: `HKHealthStore` is documented as thread-safe, and
/// the only mutable state, `observers`, is guarded by `lock`.
public final class HealthKitDataSource: HealthDataSource, @unchecked Sendable {
    public static var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private let store = HKHealthStore()
    private let lock = NSLock()
    private var observers: [HKObserverQuery] = []

    public init() {}

    // MARK: Authorization

    /// Shows the system sheet for one group. iOS never reveals whether read
    /// access was granted, so this only reports whether the sheet ran.
    public func requestAuthorization(for group: PermissionGroup) async throws {
        let types = Set(group.dataTypes.map(HealthKitMapping.sampleType(for:)) as [HKObjectType])
        try await store.requestAuthorization(toShare: [], read: types)
    }

    // MARK: HealthDataSource

    public func changes(
        for type: HealthDataType,
        since anchor: Data?,
        earliestStart: Date,
        limit: Int
    ) async throws -> ChangeBatch {
        let hkAnchor = try HealthKitMapping.unarchiveAnchor(anchor)
        let predicate = HKQuery.predicateForSamples(withStart: earliestStart, end: nil, options: .strictStartDate)

        if let kind = type.quantityKind {
            let page = try await fetch(
                .quantitySample(type: HealthKitMapping.quantityType(for: kind), predicate: predicate),
                anchor: hkAnchor,
                limit: limit
            )
            return page.batch {
                $0.quantitySamples = page.added.map { HealthKitMapping.quantitySample($0, kind: kind) }
            }
        }
        if let kind = type.categoryKind {
            let page = try await fetch(
                .categorySample(type: HealthKitMapping.categoryType(for: kind), predicate: predicate),
                anchor: hkAnchor,
                limit: limit
            )
            return page.batch { $0.categoryEvents = page.added.map { HealthKitMapping.categoryEvent($0, kind: kind) } }
        }
        switch type {
        case .sleep:
            let page = try await fetch(
                .categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate),
                anchor: hkAnchor,
                limit: limit
            )
            return page.batch { $0.sleepIntervals = page.added.compactMap(HealthKitMapping.sleepInterval) }
        case .workouts:
            let page = try await fetch(.workout(predicate), anchor: hkAnchor, limit: limit)
            return page.batch { $0.workouts = page.added.map(HealthKitMapping.workout) }
        case .stateOfMind:
            let page = try await fetch(
                .sample(type: HealthKitMapping.sampleType(for: .stateOfMind), predicate: predicate),
                anchor: hkAnchor,
                limit: limit
            )
            return page.batch {
                $0.statesOfMind = page.added.compactMap { ($0 as? HKStateOfMind).map(HealthKitMapping.stateOfMind) }
            }
        case .electrocardiogram:
            let page = try await fetch(
                .sample(type: HealthKitMapping.sampleType(for: .electrocardiogram), predicate: predicate),
                anchor: hkAnchor,
                limit: limit
            )
            return page.batch {
                $0.ecgRecords = page.added.compactMap { ($0 as? HKElectrocardiogram).map(HealthKitMapping.ecgRecord) }
            }
        default:
            preconditionFailure("Unmapped type \(type.rawValue)")
        }
    }

    private struct Page<Sample: HKSample> {
        let added: [Sample]
        let deleted: [UUID]
        let anchor: Data
        let hasMore: Bool

        func batch(_ fill: (inout ChangeBatch) -> Void) -> ChangeBatch {
            var batch = ChangeBatch(deletedIDs: deleted, newAnchor: anchor, hasMore: hasMore)
            fill(&batch)
            return batch
        }
    }

    private func fetch<Sample: HKSample>(_ predicate: HKSamplePredicate<Sample>, anchor: HKQueryAnchor?, limit: Int)
        async throws -> Page<Sample>
    {
        let descriptor = HKAnchoredObjectQueryDescriptor(predicates: [predicate], anchor: anchor, limit: limit)
        let result = try await descriptor.result(for: store)
        return Page(
            added: result.addedSamples,
            deleted: result.deletedObjects.map(\.uuid),
            anchor: try HealthKitMapping.archive(result.newAnchor),
            hasMore: result.addedSamples.count + result.deletedObjects.count >= limit
        )
    }

    // MARK: Write-back

    /// Asks to write mood and drinks (and read them, so they sync back).
    public func requestWriteAuthorization() async throws {
        let types = Set(HealthWrite.writableTypes.map(HealthKitMapping.sampleType(for:)))
        try await store.requestAuthorization(toShare: types, read: Set(types.map { $0 as HKObjectType }))
    }

    /// Whether Vivra may currently write `type`. (Unlike reading, iOS does
    /// report write permission.)
    public func canWrite(_ type: HealthDataType) -> Bool {
        store.authorizationStatus(for: HealthKitMapping.sampleType(for: type)) == .sharingAuthorized
    }

    /// Saves the sample for `write` and returns its UUID.
    public func save(_ write: HealthWrite, at date: Date) async throws -> UUID {
        let sample = HealthKitMapping.sample(for: write, at: date)
        try await store.save(sample)
        return sample.uuid
    }

    /// Deletes a sample Vivra wrote. HealthKit only lets an app delete its
    /// own samples, so this can't touch anything else.
    public func deleteSample(id: UUID, of type: HealthDataType) async throws {
        _ = try await store.deleteObjects(
            of: HealthKitMapping.sampleType(for: type),
            predicate: HKQuery.predicateForObject(with: id)
        )
    }

    // MARK: Observation

    /// Registers an observer query per type and enables background delivery.
    /// `onChange` runs for each change notification; HealthKit is told the
    /// update was handled only after it returns (i.e. after the store commit).
    /// Call from `application(_:didFinishLaunchingWithOptions:)` so
    /// background launches are handled.
    public func startObserving(
        _ types: [HealthDataType] = HealthDataType.allCases,
        onChange: @escaping @Sendable (HealthDataType) async -> Void
    ) {
        stopObserverQueries()
        var queries: [HKObserverQuery] = []
        for type in types {
            let sampleType = HealthKitMapping.sampleType(for: type)
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { _, completion, error in
                let box = CompletionBox(completion)
                if let error {
                    Log.sync.failure("Observer query failed", code: (error as NSError).code)
                    box.call()
                    return
                }
                Task {
                    await onChange(type)
                    box.call()
                }
            }
            store.execute(query)
            queries.append(query)

            store.enableBackgroundDelivery(for: sampleType, frequency: Self.frequency(for: type)) { _, error in
                if let error { Log.sync.failure("Enable background delivery failed", code: (error as NSError).code) }
            }
        }
        lock.withLock { observers = queries }
    }

    /// Stops observer queries and turns off all background delivery.
    public func stopObserving() async {
        stopObserverQueries()
        do {
            try await store.disableAllBackgroundDelivery()
        } catch {
            Log.sync.failure("Disable background delivery failed", code: (error as NSError).code)
        }
    }

    private func stopObserverQueries() {
        let queries = lock.withLock {
            defer { observers = [] }
            return observers
        }
        for query in queries { store.stop(query) }
    }

    static func frequency(for type: HealthDataType) -> HKUpdateFrequency {
        switch type {
        case .sleep, .workouts, .stateOfMind, .electrocardiogram, .irregularRhythm, .mindfulSession: .immediate
        case .vo2Max, .bodyMass, .bodyFatPercentage, .appleSleepingWristTemperature: .daily
        default: .hourly
        }
    }
}

/// HealthKit's completion handler isn't marked `Sendable`, but HealthKit
/// documents it as callable from any thread once processing is done.
private struct CompletionBox: @unchecked Sendable {
    let completion: HKObserverQueryCompletionHandler

    init(_ completion: @escaping HKObserverQueryCompletionHandler) {
        self.completion = completion
    }

    func call() { completion() }
}
