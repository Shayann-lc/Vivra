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
        case .immediately: "Immediately"
        case .oneMinute: "After 1 minute"
        case .fiveMinutes: "After 5 minutes"
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
    }

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
        // The didSet observers above wrote defaults back; remove them again.
        for key in Key.allCases { defaults.removeObject(forKey: key.rawValue) }
    }

    /// True when nothing is stored.
    var isEmpty: Bool {
        Key.allCases.allSatisfy { defaults.object(forKey: $0.rawValue) == nil }
    }
}
