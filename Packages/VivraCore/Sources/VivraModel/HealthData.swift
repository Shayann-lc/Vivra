import Foundation

/// Where a HealthKit object came from. Used to resolve overlapping sources
/// and to apply source policies (see `SourcePolicy` in InsightEngine).
public struct SourceInfo: Codable, Sendable, Hashable {
    public let bundleIdentifier: String
    public let name: String

    public init(bundleIdentifier: String, name: String) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }
}

/// HealthKit quantity types Vivra reads. Each has one canonical unit, and
/// values are always stored in it. Case names match `HealthDataType` cases.
public enum QuantityKind: String, Codable, Sendable, CaseIterable {
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

    public var unit: QuantityUnit {
        switch self {
        case .heartRate, .restingHeartRate, .walkingHeartRateAverage: .beatsPerMinute
        case .heartRateVariabilitySDNN: .milliseconds
        case .vo2Max: .millilitersPerKilogramMinute
        case .stepCount, .numberOfAlcoholicBeverages: .count
        case .activeEnergyBurned, .basalEnergyBurned, .dietaryEnergyConsumed: .kilocalories
        case .appleExerciseTime: .minutes
        case .distanceWalkingRunning: .meters
        case .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal: .grams
        case .dietaryWater: .milliliters
        case .dietaryCaffeine: .milligrams
        case .bodyMass: .kilograms
        case .bodyFatPercentage, .oxygenSaturation: .percent
        case .respiratoryRate: .breathsPerMinute
        case .appleSleepingWristTemperature: .degreesCelsius
        }
    }

    public var aggregation: Aggregation {
        switch self {
        case .stepCount, .activeEnergyBurned, .basalEnergyBurned, .appleExerciseTime, .distanceWalkingRunning:
            .cumulativeActivity
        case .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal, .dietaryWater,
            .dietaryCaffeine, .numberOfAlcoholicBeverages:
            .cumulativeIntake
        case .heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .walkingHeartRateAverage, .vo2Max, .bodyMass,
            .bodyFatPercentage, .respiratoryRate, .oxygenSaturation, .appleSleepingWristTemperature:
            .average
        }
    }
}

/// How samples of a kind combine into a daily value.
public enum Aggregation: Sendable {
    /// Daily mean of samples.
    case average
    /// Daily total. iPhone and Watch both record these, so summing every
    /// source double-counts: the daily value is the largest single source.
    case cumulativeActivity
    /// Daily total across sources (separate apps log separate meals).
    case cumulativeIntake
}

public enum QuantityUnit: String, Codable, Sendable {
    case beatsPerMinute
    case milliseconds
    case millilitersPerKilogramMinute
    case count
    case kilocalories
    case minutes
    case meters
    case grams
    case milliliters
    case milligrams
    case kilograms
    /// 0–100. HealthKit's percent unit is a fraction; the adapter converts.
    case percent
    case breathsPerMinute
    case degreesCelsius
}

public struct QuantitySample: Codable, Sendable, Hashable, Identifiable {
    /// The HealthKit object UUID.
    public let id: UUID
    public let kind: QuantityKind
    public let start: Date
    public let end: Date
    /// In `kind.unit`.
    public let value: Double
    public let source: SourceInfo

    public init(id: UUID, kind: QuantityKind, start: Date, end: Date, value: Double, source: SourceInfo) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.value = value
        self.source = source
    }
}

/// Mirrors `HKCategoryValueSleepAnalysis`.
public enum SleepStage: String, Codable, Sendable, CaseIterable {
    case inBed
    case awake
    case asleepUnspecified
    case core
    case deep
    case rem

    public var isAsleep: Bool {
        switch self {
        case .asleepUnspecified, .core, .deep, .rem: true
        case .inBed, .awake: false
        }
    }

    /// Stages only a device with sleep staging (e.g. Apple Watch) records.
    public var isStaged: Bool {
        switch self {
        case .core, .deep, .rem: true
        case .inBed, .awake, .asleepUnspecified: false
        }
    }
}

public struct SleepInterval: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let stage: SleepStage
    public let start: Date
    public let end: Date
    public let source: SourceInfo

    public init(id: UUID, stage: SleepStage, start: Date, end: Date, source: SourceInfo) {
        self.id = id
        self.stage = stage
        self.start = start
        self.end = end
        self.source = source
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

public struct Workout: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    /// `HKWorkoutActivityType.rawValue`.
    public let activityType: UInt
    public let start: Date
    public let end: Date
    public let duration: TimeInterval
    public let activeEnergyKilocalories: Double?
    public let distanceMeters: Double?
    public let source: SourceInfo

    public init(
        id: UUID,
        activityType: UInt,
        start: Date,
        end: Date,
        duration: TimeInterval,
        activeEnergyKilocalories: Double?,
        distanceMeters: Double?,
        source: SourceInfo
    ) {
        self.id = id
        self.activityType = activityType
        self.start = start
        self.end = end
        self.duration = duration
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.distanceMeters = distanceMeters
        self.source = source
    }
}

/// HealthKit category types other than sleep. Case names match
/// `HealthDataType` cases.
public enum CategoryKind: String, Codable, Sendable, CaseIterable {
    /// One per hour; `value` is 0 when the person stood (mirrors
    /// `HKCategoryValueAppleStandHour`).
    case standHour
    /// A mindful session; its length is the time.
    case mindfulSession
    /// An irregular rhythm notification. Listed only, never analysed.
    case irregularRhythm
}

public struct CategoryEvent: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let kind: CategoryKind
    public let start: Date
    public let end: Date
    public let value: Int
    public let source: SourceInfo

    public init(id: UUID, kind: CategoryKind, start: Date, end: Date, value: Int, source: SourceInfo) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.value = value
        self.source = source
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// A State of Mind entry (iOS 18+).
public struct StateOfMindSample: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case momentaryEmotion
        case dailyMood
    }

    public let id: UUID
    public let date: Date
    public let kind: Kind
    /// −1 (very unpleasant) to 1 (very pleasant).
    public let valence: Double
    /// `HKStateOfMind.Label` raw values.
    public let labels: [Int]
    /// `HKStateOfMind.Association` raw values.
    public let associations: [Int]
    public let source: SourceInfo

    public init(
        id: UUID,
        date: Date,
        kind: Kind,
        valence: Double,
        labels: [Int],
        associations: [Int],
        source: SourceInfo
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.valence = valence
        self.labels = labels
        self.associations = associations
        self.source = source
    }
}

/// An ECG recording: the date and Apple's classification only. Vivra lists
/// these and never interprets or analyses them.
public struct ECGRecord: Codable, Sendable, Hashable, Identifiable {
    /// Mirrors `HKElectrocardiogram.Classification`.
    public enum Classification: String, Codable, Sendable, CaseIterable {
        case notSet
        case sinusRhythm
        case atrialFibrillation
        case inconclusiveLowHeartRate
        case inconclusiveHighHeartRate
        case inconclusivePoorReading
        case inconclusiveOther
        case unrecognized
    }

    public let id: UUID
    public let date: Date
    public let classification: Classification
    public let source: SourceInfo

    public init(id: UUID, date: Date, classification: Classification, source: SourceInfo) {
        self.id = id
        self.date = date
        self.classification = classification
        self.source = source
    }
}
