import Foundation

/// A daily metric the engine reports on. Raw values are stored in saved
/// reports, so existing cases must never be renamed.
public enum Metric: String, Codable, Sendable, CaseIterable {
    // Sleep and heart
    /// Time asleep for the night ending that morning.
    case sleepDuration
    case restingHeartRate
    case heartRateVariability
    case walkingHeartRateAverage
    case vo2Max
    // Workouts
    /// Workout minutes that day (or the total over a period, in weekly averages).
    case workoutMinutes
    case workoutCount
    // Activity
    case steps
    case activeEnergy
    case exerciseMinutes
    case distance
    case standHours
    // Mind
    case mindfulMinutes
    /// 1–5, from Quick Log and State of Mind.
    case mood
    /// 1–5, from Quick Log.
    case energyLevel
    /// 1–5, from Quick Log.
    case stressLevel
    // Nutrition and hydration
    case dietaryEnergy
    case protein
    case carbohydrates
    case fat
    case water
    case caffeine
    case alcohol
    // Body
    case weight
    case bodyFat
    case respiratoryRate
    case bloodOxygen
    case wristTemperature

    public var unit: MetricUnit {
        switch self {
        case .sleepDuration: .seconds
        case .restingHeartRate, .walkingHeartRateAverage: .beatsPerMinute
        case .heartRateVariability: .milliseconds
        case .vo2Max: .millilitersPerKilogramMinute
        case .workoutMinutes, .exerciseMinutes, .mindfulMinutes: .minutes
        case .workoutCount: .count
        case .steps: .steps
        case .activeEnergy, .dietaryEnergy: .kilocalories
        case .distance: .meters
        case .standHours: .hours
        case .mood, .energyLevel, .stressLevel: .scale
        case .protein, .carbohydrates, .fat: .grams
        case .water: .milliliters
        case .caffeine: .milligrams
        case .alcohol: .drinks
        case .weight: .kilograms
        case .bodyFat, .bloodOxygen: .percent
        case .respiratoryRate: .breathsPerMinute
        case .wristTemperature: .degreesCelsius
        }
    }

    /// Logged only when it happens (a missing day means none), so missing
    /// days between the first and last record count as zero.
    var missingMeansZero: Bool {
        switch self {
        case .alcohol, .caffeine, .mindfulMinutes, .workoutMinutes, .workoutCount: true
        default: false
        }
    }

    /// Differences, trends and anomalies smaller than this aren't reported.
    var minimumEffect: Double {
        switch self {
        case .sleepDuration: 15 * 60
        case .restingHeartRate, .walkingHeartRateAverage: 1
        case .heartRateVariability: 3
        case .vo2Max: 1
        case .workoutMinutes, .exerciseMinutes: 10
        case .workoutCount: 1
        case .steps: 1_000
        case .activeEnergy: 50
        case .distance: 500
        case .standHours: 1
        case .mindfulMinutes: 5
        case .mood, .energyLevel, .stressLevel: 0.5
        case .dietaryEnergy: 150
        case .protein, .carbohydrates, .fat: 10
        case .water: 250
        case .caffeine: 50
        case .alcohol: 1
        case .weight: 0.5
        case .bodyFat: 0.5
        case .respiratoryRate: 1
        case .bloodOxygen: 1
        case .wristTemperature: 0.2
        }
    }

    /// Values outside these ranges get the "consider talking with a
    /// professional" note. The UI never says what a value means.
    /// - Resting heart rate: the American Heart Association gives 60–100 bpm
    ///   for adults and notes very fit people are often lower; 40 is used as
    ///   the lower bound.
    /// - Blood oxygen: 90% is the threshold commonly cited for low oxygen
    ///   (hypoxaemia); readings of 95–100% are typical.
    /// - Respiratory rate: 12–20 breaths/min is the usual adult resting
    ///   reference; the bounds are widened to 10–24 to avoid noise from
    ///   overnight wearable estimates.
    var typicalRange: ClosedRange<Double>? {
        switch self {
        case .restingHeartRate: 40...100
        case .bloodOxygen: 90...100
        case .respiratoryRate: 10...24
        default: nil
        }
    }

    func isOutsideTypicalRange(_ value: Double) -> Bool {
        typicalRange.map { !$0.contains(value) } ?? false
    }
}

public enum MetricUnit: String, Codable, Sendable {
    case seconds
    case beatsPerMinute
    case milliseconds
    case millilitersPerKilogramMinute
    case minutes
    case count
    case steps
    case kilocalories
    case meters
    case hours
    case scale
    case grams
    case milliliters
    case milligrams
    case drinks
    case kilograms
    case percent
    case breathsPerMinute
    case degreesCelsius
}
