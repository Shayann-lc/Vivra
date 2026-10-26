import Foundation
import HealthKit
import SyncCore
import VivraModel

/// Conversions between HealthKit objects and Vivra's value types.
enum HealthKitMapping {
    static func sampleType(for type: HealthDataType) -> HKSampleType {
        switch type {
        case .sleep: HKCategoryType(.sleepAnalysis)
        case .heartRate: HKQuantityType(.heartRate)
        case .restingHeartRate: HKQuantityType(.restingHeartRate)
        case .heartRateVariabilitySDNN: HKQuantityType(.heartRateVariabilitySDNN)
        case .walkingHeartRateAverage: HKQuantityType(.walkingHeartRateAverage)
        case .vo2Max: HKQuantityType(.vo2Max)
        case .workouts: HKWorkoutType.workoutType()
        }
    }

    static func unit(for kind: QuantityKind) -> HKUnit {
        switch kind.unit {
        case .beatsPerMinute: .count().unitDivided(by: .minute())
        case .milliseconds: .secondUnit(with: .milli)
        case .millilitersPerKilogramMinute: HKUnit(from: "ml/kg*min")
        }
    }

    static func source(of object: HKObject) -> SourceInfo {
        let source = object.sourceRevision.source
        return SourceInfo(bundleIdentifier: source.bundleIdentifier, name: source.name)
    }

    static func quantitySample(_ sample: HKQuantitySample, kind: QuantityKind) -> QuantitySample {
        QuantitySample(
            id: sample.uuid,
            kind: kind,
            start: sample.startDate,
            end: sample.endDate,
            value: sample.quantity.doubleValue(for: unit(for: kind)),
            source: source(of: sample)
        )
    }

    /// Nil for values this version doesn't know.
    static func sleepStage(_ value: Int) -> SleepStage? {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .inBed: .inBed
        case .awake: .awake
        case .asleepUnspecified: .asleepUnspecified
        case .asleepCore: .core
        case .asleepDeep: .deep
        case .asleepREM: .rem
        default: nil
        }
    }

    static func sleepInterval(_ sample: HKCategorySample) -> SleepInterval? {
        guard let stage = sleepStage(sample.value) else { return nil }
        return SleepInterval(
            id: sample.uuid, stage: stage, start: sample.startDate, end: sample.endDate, source: source(of: sample))
    }

    /// Distance types, in the order to try. A workout records at most one.
    private static let distanceTypes: [HKQuantityType] = [
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.distanceCycling),
        HKQuantityType(.distanceSwimming),
        HKQuantityType(.distanceWheelchair),
        HKQuantityType(.distanceRowing),
        HKQuantityType(.distancePaddleSports),
        HKQuantityType(.distanceCrossCountrySkiing),
        HKQuantityType(.distanceSkatingSports),
        HKQuantityType(.distanceDownhillSnowSports),
    ]

    static func workout(_ workout: HKWorkout) -> Workout {
        let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()
        let distance = distanceTypes.lazy.compactMap { workout.statistics(for: $0)?.sumQuantity() }.first
        return Workout(
            id: workout.uuid,
            activityType: workout.workoutActivityType.rawValue,
            start: workout.startDate,
            end: workout.endDate,
            duration: workout.duration,
            activeEnergyKilocalories: energy?.doubleValue(for: .kilocalorie()),
            distanceMeters: distance?.doubleValue(for: .meter()),
            source: source(of: workout)
        )
    }

    static func archive(_ anchor: HKQueryAnchor) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    }

    static func unarchiveAnchor(_ data: Data?) throws -> HKQueryAnchor? {
        guard let data else { return nil }
        return try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }
}
