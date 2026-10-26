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

        switch type {
        case .sleep:
            let descriptor = HKAnchoredObjectQueryDescriptor(
                predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
                anchor: hkAnchor,
                limit: limit
            )
            let result = try await descriptor.result(for: store)
            return try ChangeBatch(
                sleepIntervals: result.addedSamples.compactMap(HealthKitMapping.sleepInterval),
                deletedIDs: result.deletedObjects.map(\.uuid),
                newAnchor: HealthKitMapping.archive(result.newAnchor),
                hasMore: result.addedSamples.count + result.deletedObjects.count >= limit
            )

        case .workouts:
            let descriptor = HKAnchoredObjectQueryDescriptor(
                predicates: [.workout(predicate)],
                anchor: hkAnchor,
                limit: limit
            )
            let result = try await descriptor.result(for: store)
            return try ChangeBatch(
                workouts: result.addedSamples.map(HealthKitMapping.workout),
                deletedIDs: result.deletedObjects.map(\.uuid),
                newAnchor: HealthKitMapping.archive(result.newAnchor),
                hasMore: result.addedSamples.count + result.deletedObjects.count >= limit
            )

        case .heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .walkingHeartRateAverage, .vo2Max:
            let kind = type.quantityKind!
            let quantityType = HealthKitMapping.sampleType(for: type) as! HKQuantityType
            let descriptor = HKAnchoredObjectQueryDescriptor(
                predicates: [.quantitySample(type: quantityType, predicate: predicate)],
                anchor: hkAnchor,
                limit: limit
            )
            let result = try await descriptor.result(for: store)
            return try ChangeBatch(
                quantitySamples: result.addedSamples.map { HealthKitMapping.quantitySample($0, kind: kind) },
                deletedIDs: result.deletedObjects.map(\.uuid),
                newAnchor: HealthKitMapping.archive(result.newAnchor),
                hasMore: result.addedSamples.count + result.deletedObjects.count >= limit
            )
        }
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
                let completion = CompletionBox(completion)
                if let error {
                    Log.sync.failure("Observer query failed", code: (error as NSError).code)
                    completion.call()
                    return
                }
                Task {
                    await onChange(type)
                    completion.call()
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
        case .sleep, .workouts: .immediate
        case .heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .walkingHeartRateAverage: .hourly
        case .vo2Max: .daily
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
