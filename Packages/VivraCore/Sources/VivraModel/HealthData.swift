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

/// Quantity types synced in Phase 1. Each has one canonical unit; values are
/// always stored in it.
public enum QuantityKind: String, Codable, Sendable, CaseIterable {
    case heartRate
    case restingHeartRate
    case heartRateVariabilitySDNN
    case walkingHeartRateAverage
    case vo2Max

    public var unit: QuantityUnit {
        switch self {
        case .heartRate, .restingHeartRate, .walkingHeartRateAverage: .beatsPerMinute
        case .heartRateVariabilitySDNN: .milliseconds
        case .vo2Max: .millilitersPerKilogramMinute
        }
    }
}

public enum QuantityUnit: String, Codable, Sendable {
    case beatsPerMinute
    case milliseconds
    case millilitersPerKilogramMinute
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
