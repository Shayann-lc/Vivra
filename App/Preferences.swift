import Foundation
import Observation

enum AppLockTimeout: Int, CaseIterable, Identifiable {
    case immediately = 0
    case oneMinute = 60
    case fiveMinutes = 300

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }

    var label: String {
        switch self {
        case .immediately: String(localized: "Immediately")
        case .oneMinute: String(localized: "After 1 minute")
        case .fiveMinutes: String(localized: "After 5 minutes")
        }
    }
}

/// Small, non-health settings kept in `UserDefaults`. Health data never goes
/// here: it lives only in the encrypted database.
@MainActor
@Observable
final class Preferences {
    /// Bump when the disclaimer text changes materially, so it's shown again.
    static let currentDisclaimerVersion = 1

    private enum Key: String, CaseIterable {
        case onboardingCompleted
        case acceptedDisclaimerVersion
        case appLockEnabled
        case appLockTimeout
        case writeBackEnabled
        case requestedPermissionRevisions
        case remindersEnabled
        case reminderMinutes
        case reminderOffered
        case todayCardOrder
        case hiddenTodayCards
    }

    @ObservationIgnored private let defaults: UserDefaults
    /// The defaults domain to wipe on "delete everything" (the app's bundle
    /// identifier, or a test suite name).
    @ObservationIgnored private let domainName: String?

    var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Key.onboardingCompleted.rawValue) }
    }
    var acceptedDisclaimerVersion: Int {
        didSet { defaults.set(acceptedDisclaimerVersion, forKey: Key.acceptedDisclaimerVersion.rawValue) }
    }
    var appLockEnabled: Bool {
        didSet { defaults.set(appLockEnabled, forKey: Key.appLockEnabled.rawValue) }
    }
    var appLockTimeout: AppLockTimeout {
        didSet { defaults.set(appLockTimeout.rawValue, forKey: Key.appLockTimeout.rawValue) }
    }
    /// Save mood and drinks to Apple Health. Off by default.
    var writeBackEnabled: Bool {
        didSet { defaults.set(writeBackEnabled, forKey: Key.writeBackEnabled.rawValue) }
    }
    var remindersEnabled: Bool {
        didSet { defaults.set(remindersEnabled, forKey: Key.remindersEnabled.rawValue) }
    }
    /// Minutes after midnight.
    var reminderMinutes: Int {
        didSet { defaults.set(reminderMinutes, forKey: Key.reminderMinutes.rawValue) }
    }
    /// Whether the one-time reminder offer has been shown.
    var reminderOffered: Bool {
        didSet { defaults.set(reminderOffered, forKey: Key.reminderOffered.rawValue) }
    }
    /// Today's detail cards in display order, including hidden ones.
    var todayCardOrder: [TodayCard] {
        didSet { defaults.set(todayCardOrder.map(\.rawValue), forKey: Key.todayCardOrder.rawValue) }
    }
    var hiddenTodayCards: Set<TodayCard> {
        didSet { defaults.set(hiddenTodayCards.map(\.rawValue).sorted(), forKey: Key.hiddenTodayCards.rawValue) }
    }
    /// The revision of each permission group last requested (group id → revision).
    var requestedPermissionRevisions: [String: Int] {
        didSet { defaults.set(requestedPermissionRevisions, forKey: Key.requestedPermissionRevisions.rawValue) }
    }

    init(defaults: UserDefaults, domainName: String?) {
        self.defaults = defaults
        self.domainName = domainName
        onboardingCompleted = defaults.bool(forKey: Key.onboardingCompleted.rawValue)
        acceptedDisclaimerVersion = defaults.integer(forKey: Key.acceptedDisclaimerVersion.rawValue)
        appLockEnabled = defaults.bool(forKey: Key.appLockEnabled.rawValue)
        appLockTimeout = AppLockTimeout(rawValue: defaults.integer(forKey: Key.appLockTimeout.rawValue)) ?? .immediately
        writeBackEnabled = defaults.bool(forKey: Key.writeBackEnabled.rawValue)
        requestedPermissionRevisions =
            defaults.dictionary(forKey: Key.requestedPermissionRevisions.rawValue) as? [String: Int] ?? [:]
        remindersEnabled = defaults.bool(forKey: Key.remindersEnabled.rawValue)
        reminderMinutes = defaults.object(forKey: Key.reminderMinutes.rawValue) as? Int ?? 19 * 60
        reminderOffered = defaults.bool(forKey: Key.reminderOffered.rawValue)
        todayCardOrder = TodayCard.ordered(defaults.stringArray(forKey: Key.todayCardOrder.rawValue) ?? [])
        hiddenTodayCards = Set(
            (defaults.stringArray(forKey: Key.hiddenTodayCards.rawValue) ?? []).compactMap(TodayCard.init))
    }

    var visibleTodayCards: [TodayCard] { todayCardOrder.filter { !hiddenTodayCards.contains($0) } }

    var hasAcceptedCurrentDisclaimer: Bool {
        acceptedDisclaimerVersion >= Self.currentDisclaimerVersion
    }

    /// Removes every stored preference and resets the in-memory values.
    func removeAll() {
        for key in Key.allCases { defaults.removeObject(forKey: key.rawValue) }
        if let domainName { defaults.removePersistentDomain(forName: domainName) }
        onboardingCompleted = false
        acceptedDisclaimerVersion = 0
        appLockEnabled = false
        appLockTimeout = .immediately
        writeBackEnabled = false
        requestedPermissionRevisions = [:]
        remindersEnabled = false
        reminderMinutes = 19 * 60
        reminderOffered = false
        todayCardOrder = TodayCard.defaultOrder
        hiddenTodayCards = []
        // The didSet observers above wrote defaults back; remove them again.
        for key in Key.allCases { defaults.removeObject(forKey: key.rawValue) }
    }

    /// True when nothing is stored.
    var isEmpty: Bool {
        Key.allCases.allSatisfy { defaults.object(forKey: $0.rawValue) == nil }
    }
}

/// Detail cards on the Today screen, which people can show, hide and reorder.
enum TodayCard: String, CaseIterable, Identifiable {
    case sleep
    case heart
    case activity
    case workouts
    case logged
    case body

    var id: String { rawValue }
    static let defaultOrder: [TodayCard] = [.sleep, .heart, .activity, .workouts, .logged, .body]

    /// Saved order first, then any cards added since, in default order.
    static func ordered(_ saved: [String]) -> [TodayCard] {
        let known = saved.compactMap(TodayCard.init)
        return known + defaultOrder.filter { !known.contains($0) }
    }

    var title: String {
        switch self {
        case .sleep: String(localized: "Sleep")
        case .heart: String(localized: "Heart")
        case .activity: String(localized: "Activity")
        case .workouts: String(localized: "Workouts")
        case .logged: String(localized: "Logged today")
        case .body: String(localized: "Body")
        }
    }
}
