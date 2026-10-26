import Foundation
import Testing

@testable import Vivra

@MainActor
@Suite struct PreferencesTests {
    @Test func valuesPersistAndRemoveAllClearsThem() {
        let suiteName = "app.vivra.preferencetests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let defaults = UserDefaults(suiteName: suiteName)!

        let preferences = Preferences(defaults: defaults, domainName: suiteName)
        #expect(preferences.isEmpty)
        preferences.onboardingCompleted = true
        preferences.appLockTimeout = .fiveMinutes

        let reloaded = Preferences(defaults: defaults, domainName: suiteName)
        #expect(reloaded.onboardingCompleted)
        #expect(reloaded.appLockTimeout == .fiveMinutes)

        reloaded.removeAll()
        #expect(reloaded.isEmpty)
        #expect(!reloaded.onboardingCompleted)
    }

    @Test func appLockEngagesOnlyAfterTheTimeout() {
        let suiteName = "app.vivra.locktests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let preferences = Preferences(defaults: UserDefaults(suiteName: suiteName)!, domainName: suiteName)
        preferences.appLockEnabled = true
        preferences.appLockTimeout = .oneMinute
        let lock = AppLock(preferences: preferences)
        lock.reset()
        let start = Date(timeIntervalSince1970: 1_775_000_000)

        lock.didEnterBackground(at: start)
        lock.didBecomeActive(at: start.addingTimeInterval(30))
        #expect(!lock.isLocked)

        lock.didEnterBackground(at: start)
        lock.didBecomeActive(at: start.addingTimeInterval(61))
        #expect(lock.isLocked)
    }
}
