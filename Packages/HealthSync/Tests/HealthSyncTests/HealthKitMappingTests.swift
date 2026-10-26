import Foundation
import HealthKit
import SyncCore
import Testing
import VivraModel

@testable import HealthSync

@Suite struct HealthKitMappingTests {
    private let start = Date(timeIntervalSince1970: 1_775_000_000)

    @Test func quantitySamplesUseCanonicalUnits() {
        let hrv = HKQuantitySample(
            type: HKQuantityType(.heartRateVariabilitySDNN),
            quantity: HKQuantity(unit: .secondUnit(with: .milli), doubleValue: 45),
            start: start,
            end: start
        )
        #expect(HealthKitMapping.quantitySample(hrv, kind: .heartRateVariabilitySDNN).value == 45)

        let heartRate = HKQuantitySample(
            type: HKQuantityType(.restingHeartRate),
            quantity: HKQuantity(unit: .count().unitDivided(by: .second()), doubleValue: 1),
            start: start,
            end: start
        )
        #expect(HealthKitMapping.quantitySample(heartRate, kind: .restingHeartRate).value == 60)

        let vo2 = HKQuantitySample(
            type: HKQuantityType(.vo2Max),
            quantity: HKQuantity(unit: HKUnit(from: "ml/kg*min"), doubleValue: 41.5),
            start: start,
            end: start
        )
        let mapped = HealthKitMapping.quantitySample(vo2, kind: .vo2Max)
        #expect(mapped.value == 41.5)
        #expect(mapped.id == vo2.uuid)
    }

    @Test func sleepStagesMap() {
        #expect(HealthKitMapping.sleepStage(HKCategoryValueSleepAnalysis.inBed.rawValue) == .inBed)
        #expect(HealthKitMapping.sleepStage(HKCategoryValueSleepAnalysis.asleepDeep.rawValue) == .deep)
        #expect(HealthKitMapping.sleepStage(HKCategoryValueSleepAnalysis.asleepREM.rawValue) == .rem)
        #expect(HealthKitMapping.sleepStage(999) == nil)

        let sample = HKCategorySample(
            type: HKCategoryType(.sleepAnalysis),
            value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            start: start,
            end: start.addingTimeInterval(3600)
        )
        let interval = HealthKitMapping.sleepInterval(sample)
        #expect(interval?.stage == .core)
        #expect(interval?.duration == 3600)
    }

    @Test func everyTypeHasASampleTypeAndFrequency() {
        for type in HealthDataType.allCases {
            _ = HealthKitMapping.sampleType(for: type)
            _ = HealthKitDataSource.frequency(for: type)
        }
        #expect(HealthKitMapping.sampleType(for: .workouts) == HKWorkoutType.workoutType())
    }
}
