import VivraModel

/// What a log entry writes to Apple Health when write-back is on.
public enum HealthWrite: Sendable, Equatable {
    /// A momentary State of Mind, valence −1…1.
    case stateOfMind(valence: Double)
    case quantity(QuantityKind, value: Double)

    /// The data type written, for permissions and deletes.
    public var dataType: HealthDataType {
        switch self {
        case .stateOfMind: .stateOfMind
        case .quantity(let kind, _): HealthDataType(kind)
        }
    }

    /// Types Vivra asks to write when write-back is turned on.
    public static let writableTypes: [HealthDataType] = [
        .stateOfMind, .dietaryWater, .dietaryCaffeine, .numberOfAlcoholicBeverages,
    ]

    /// Mood maps 1–5 onto valence −1…1. Drinks map to water, caffeine or
    /// alcoholic beverages. Energy, stress, meals and notes have no Health
    /// equivalent and stay in Vivra.
    public static func `for`(_ entry: LogEntry) -> HealthWrite? {
        switch entry.kind {
        case .mood:
            guard let scale = entry.scale, LogEntry.scaleRange.contains(scale) else { return nil }
            return .stateOfMind(valence: Double(scale - 3) / 2)
        case .drink:
            guard let drink = entry.drink, let amount = entry.amount, amount > 0 else { return nil }
            switch drink {
            case .water: return .quantity(.dietaryWater, value: amount)
            case .coffee, .tea: return .quantity(.dietaryCaffeine, value: amount)
            case .alcohol: return .quantity(.numberOfAlcoholicBeverages, value: amount)
            }
        case .energy, .stress, .meal, .note:
            return nil
        }
    }
}
