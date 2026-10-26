/// HealthKit read permissions are requested in groups, each with its own
/// explanation screen during onboarding.
public enum PermissionGroup: String, Sendable, CaseIterable, Identifiable {
    case sleep
    case heart
    case workouts

    public var id: String { rawValue }

    public var dataTypes: [HealthDataType] {
        switch self {
        case .sleep: [.sleep]
        case .heart: [.heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .walkingHeartRateAverage, .vo2Max]
        case .workouts: [.workouts]
        }
    }
}
