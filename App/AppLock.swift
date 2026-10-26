import Foundation
import LocalAuthentication
import Observation
import VivraLogging

/// Optional Face ID / passcode lock, applied after the app has been in the
/// background for the chosen timeout.
@MainActor
@Observable
final class AppLock {
    private(set) var isLocked: Bool
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private var backgroundedAt: Date?

    init(preferences: Preferences) {
        self.preferences = preferences
        isLocked = preferences.appLockEnabled
    }

    static var canAuthenticate: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func didEnterBackground(at date: Date) {
        backgroundedAt = date
    }

    func didBecomeActive(at date: Date) {
        defer { backgroundedAt = nil }
        guard preferences.appLockEnabled, let backgroundedAt else { return }
        if date.timeIntervalSince(backgroundedAt) >= preferences.appLockTimeout.seconds {
            isLocked = true
        }
    }

    func unlock() async {
        if await authenticate(reason: "Unlock Vivra") { isLocked = false }
    }

    /// Turning the lock on requires authenticating once, so nobody can lock
    /// themselves out with a method the device doesn't support.
    func setEnabled(_ enabled: Bool) async {
        if enabled {
            guard await authenticate(reason: "Turn on App Lock") else { return }
        }
        preferences.appLockEnabled = enabled
    }

    func reset() {
        isLocked = false
        backgroundedAt = nil
    }

    private func authenticate(reason: String) async -> Bool {
        do {
            return try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            Log.app.failure("Authentication failed", code: (error as NSError).code)
            return false
        }
    }
}
