import Foundation
import HealthKit
import SyncCore
import VivraModel

/// Conversions between HealthKit objects and Vivra's value types.
enum HealthKitMapping {
    static func sampleType(for type: HealthDataType) -> HKSampleType {
        if let kind = type.quantityKind { return quantityType(for: kind) }
        if let kind = type.categoryKind { return categoryType(for: kind) }
        switch type {
        case .sleep: return HKCategoryType(.sleepAnalysis)
        case .workouts: return HKWorkoutType.workoutType()
        case .stateOfMind: return HKSampleType.stateOfMindType()
        case .electrocardiogram: return HKObjectType.electrocardiogramType()
        default: preconditionFailure("Unmapped type \(type.rawValue)")
        }
    }

    static func categoryType(for kind: CategoryKind) -> HKCategoryType {
        switch kind {
        case .standHour: HKCategoryType(.appleStandHour)
        case .mindfulSession: HKCategoryType(.mindfulSession)
        case .irregularRhythm: HKCategoryType(.irregularHeartRhythmEvent)
        }
    }

    static func quantityType(for kind: QuantityKind) -> HKQuantityType {
        switch kind {
        case .heartRate: HKQuantityType(.heartRate)
        case .restingHeartRate: HKQuantityType(.restingHeartRate)
        case .heartRateVariabilitySDNN: HKQuantityType(.heartRateVariabilitySDNN)
        case .walkingHeartRateAverage: HKQuantityType(.walkingHeartRateAverage)
        case .vo2Max: HKQuantityType(.vo2Max)
        case .stepCount: HKQuantityType(.stepCount)
        case .activeEnergyBurned: HKQuantityType(.activeEnergyBurned)
        case .basalEnergyBurned: HKQuantityType(.basalEnergyBurned)
        case .appleExerciseTime: HKQuantityType(.appleExerciseTime)
        case .distanceWalkingRunning: HKQuantityType(.distanceWalkingRunning)
        case .dietaryEnergyConsumed: HKQuantityType(.dietaryEnergyConsumed)
        case .dietaryProtein: HKQuantityType(.dietaryProtein)
        case .dietaryCarbohydrates: HKQuantityType(.dietaryCarbohydrates)
        case .dietaryFatTotal: HKQuantityType(.dietaryFatTotal)
        case .dietaryWater: HKQuantityType(.dietaryWater)
        case .dietaryCaffeine: HKQuantityType(.dietaryCaffeine)
        case .numberOfAlcoholicBeverages: HKQuantityType(.numberOfAlcoholicBeverages)
        case .bodyMass: HKQuantityType(.bodyMass)
        case .bodyFatPercentage: HKQuantityType(.bodyFatPercentage)
        case .respiratoryRate: HKQuantityType(.respiratoryRate)
        case .oxygenSaturation: HKQuantityType(.oxygenSaturation)
        case .appleSleepingWristTemperature: HKQuantityType(.appleSleepingWristTemperature)
        }
    }

    static func unit(for kind: QuantityKind) -> HKUnit {
        switch kind.unit {
        case .beatsPerMinute, .breathsPerMinute: .count().unitDivided(by: .minute())
        case .milliseconds: .secondUnit(with: .milli)
        case .millilitersPerKilogramMinute: HKUnit(from: "ml/kg*min")
        case .count: .count()
        case .kilocalories: .kilocalorie()
        case .minutes: .minute()
        case .meters: .meter()
        case .grams: .gram()
        case .milliliters: .literUnit(with: .milli)
        case .milligrams: .gramUnit(with: .milli)
        case .kilograms: .gramUnit(with: .kilo)
        case .percent: .percent()
        case .degreesCelsius: .degreeCelsius()
        }
    }

    /// Vivra stores percentages as 0–100; HealthKit's percent is a fraction.
    static func storedValue(_ quantity: HKQuantity, kind: QuantityKind) -> Double {
        let value = quantity.doubleValue(for: unit(for: kind))
        return kind.unit == .percent ? value * 100 : value
    }

    static func quantity(_ value: Double, kind: QuantityKind) -> HKQuantity {
        HKQuantity(unit: unit(for: kind), doubleValue: kind.unit == .percent ? value / 100 : value)
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
            value: storedValue(sample.quantity, kind: kind),
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

    static func categoryEvent(_ sample: HKCategorySample, kind: CategoryKind) -> CategoryEvent {
        CategoryEvent(
            id: sample.uuid,
            kind: kind,
            start: sample.startDate,
            end: sample.endDate,
            value: sample.value,
            source: source(of: sample)
        )
    }

    static func stateOfMind(_ sample: HKStateOfMind) -> StateOfMindSample {
        StateOfMindSample(
            id: sample.uuid,
            date: sample.startDate,
            kind: sample.kind == .dailyMood ? .dailyMood : .momentaryEmotion,
            valence: sample.valence,
            labels: sample.labels.map(\.rawValue),
            associations: sample.associations.map(\.rawValue),
            source: source(of: sample)
        )
    }

    static func ecgRecord(_ sample: HKElectrocardiogram) -> ECGRecord {
        let classification: ECGRecord.Classification =
            switch sample.classification {
            case .notSet: .notSet
            case .sinusRhythm: .sinusRhythm
            case .atrialFibrillation: .atrialFibrillation
            case .inconclusiveLowHeartRate: .inconclusiveLowHeartRate
            case .inconclusiveHighHeartRate: .inconclusiveHighHeartRate
            case .inconclusivePoorReading: .inconclusivePoorReading
            case .inconclusiveOther: .inconclusiveOther
            case .unrecognized: .unrecognized
            @unknown default: .unrecognized
            }
        return ECGRecord(
            id: sample.uuid, date: sample.startDate, classification: classification, source: source(of: sample))
    }

    /// The HealthKit object for a write-back.
    static func sample(for write: HealthWrite, at date: Date) -> HKSample {
        switch write {
        case .stateOfMind(let valence):
            HKStateOfMind(date: date, kind: .momentaryEmotion, valence: valence, labels: [], associations: [])
        case .quantity(let kind, let value):
            HKQuantitySample(
                type: quantityType(for: kind), quantity: quantity(value, kind: kind), start: date, end: date)
        }
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
