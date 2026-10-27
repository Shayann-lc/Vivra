/// HealthKit read permissions are requested in groups, each with its own
/// explanation screen. Onboarding asks in `allCases` order.
public enum PermissionGroup: String, Sendable, CaseIterable, Identifiable, Codable {
    case sleep
    case heart
    case activity
    case workouts
    case mind
    case nutrition
    case body

    public var id: String { rawValue }

    public var dataTypes: [HealthDataType] {
        switch self {
        case .sleep: [.sleep]
        case .heart:
            [
                .heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .walkingHeartRateAverage, .vo2Max,
                .electrocardiogram, .irregularRhythm,
            ]
        case .activity:
            [
                .stepCount, .activeEnergyBurned, .basalEnergyBurned, .appleExerciseTime, .distanceWalkingRunning,
                .standHour,
            ]
        case .workouts: [.workouts]
        case .mind: [.stateOfMind, .mindfulSession]
        case .nutrition:
            [
                .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal, .dietaryWater,
                .dietaryCaffeine, .numberOfAlcoholicBeverages,
            ]
        case .body:
            [.bodyMass, .bodyFatPercentage, .respiratoryRate, .oxygenSaturation, .appleSleepingWristTemperature]
        }
    }

    /// Bumped when a group gains types, so people who already answered are
    /// asked again for the new ones. Heart gained ECG and irregular rhythm in
    /// Phase 2.
    public var revision: Int {
        switch self {
        case .heart: 2
        case .sleep, .activity, .workouts, .mind, .nutrition, .body: 1
        }
    }

    /// What someone who finished onboarding in Phase 1 has already been asked.
    public static let phaseOneRevisions: [PermissionGroup: Int] = [.sleep: 1, .heart: 1, .workouts: 1]

    /// Groups whose current revision hasn't been requested yet.
    public static func pending(requested: [PermissionGroup: Int]) -> [PermissionGroup] {
        allCases.filter { (requested[$0] ?? 0) < $0.revision }
    }
}
