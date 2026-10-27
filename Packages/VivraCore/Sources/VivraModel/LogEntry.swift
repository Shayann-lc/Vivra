import Foundation

/// Something the person logged in Vivra.
public struct LogEntry: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case mood
        case energy
        case stress
        case drink
        case meal
        case note
    }

    public let id: UUID
    public let kind: Kind
    public let timestamp: Date
    /// 1–5 for mood, energy and stress.
    public let scale: Int?
    public let drink: Drink?
    /// For drinks, in the drink's unit (see `Drink.unit`).
    public let amount: Double?
    public let note: String?
    /// The sample written to Apple Health for this entry, when write-back is on.
    public let healthKitSampleID: UUID?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        timestamp: Date,
        scale: Int? = nil,
        drink: Drink? = nil,
        amount: Double? = nil,
        note: String? = nil,
        healthKitSampleID: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.scale = scale
        self.drink = drink
        self.amount = amount
        self.note = note
        self.healthKitSampleID = healthKitSampleID
    }

    public func with(healthKitSampleID: UUID?) -> LogEntry {
        LogEntry(
            id: id,
            kind: kind,
            timestamp: timestamp,
            scale: scale,
            drink: drink,
            amount: amount,
            note: note,
            healthKitSampleID: healthKitSampleID
        )
    }

    public static let scaleRange = 1...5
}

/// Drinks Quick Log offers, each logged in servings and stored in its own unit.
public enum Drink: String, Codable, Sendable, CaseIterable {
    case water
    case coffee
    case tea
    case alcohol

    public enum Unit: Sendable {
        case milliliters
        case milligramsCaffeine
        case standardDrinks
    }

    public var unit: Unit {
        switch self {
        case .water: .milliliters
        case .coffee, .tea: .milligramsCaffeine
        case .alcohol: .standardDrinks
        }
    }

    /// The amount one serving adds. Caffeine per cup is from USDA
    /// FoodData Central: brewed coffee about 95 mg and brewed black tea about
    /// 47 mg per 8 fl oz cup. These are estimates and are labelled as such
    /// in the UI.
    public var amountPerServing: Double {
        switch self {
        case .water: 250
        case .coffee: 95
        case .tea: 47
        case .alcohol: 1
        }
    }
}
