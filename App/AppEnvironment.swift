import Foundation
import HealthSync
import Narrative
import NarrativeCore
import VivraModel
import VivraStore

/// Everything `AppModel` depends on, so tests can swap in temporary storage,
/// a fixed clock and no HealthKit.
struct AppEnvironment {
    var storeDirectory: @Sendable () throws -> URL
    var keychainService: String
    var health: HealthKitDataSource?
    var clock: any Clock
    /// Read each time it's needed, so time zone changes are picked up.
    var calendar: @Sendable () -> DayCalendar
    var makeNarrator: @Sendable () -> (any Narrator)?

    static var live: AppEnvironment {
        AppEnvironment(
            storeDirectory: { try VivraDatabase.defaultDirectory() },
            keychainService: KeychainKeyProvider.defaultService,
            health: HealthKitDataSource.isHealthDataAvailable ? HealthKitDataSource() : nil,
            clock: SystemClock(),
            calendar: { DayCalendar(Calendar.autoupdatingCurrent) },
            makeNarrator: { FoundationModelsNarrator.isAvailable ? FoundationModelsNarrator() : nil }
        )
    }
}

extension AppEnvironment {
    /// Its own storage, a fixed clock and time zone, no HealthKit and no
    /// language model. For tests and previews.
    static func isolated(
        directory: URL,
        keychainService: String,
        now: Date,
        timeZoneIdentifier: String = "UTC"
    ) -> AppEnvironment {
        let calendar = DayCalendar(timeZone: TimeZone(identifier: timeZoneIdentifier) ?? .gmt)
        return AppEnvironment(
            storeDirectory: { directory },
            keychainService: keychainService,
            health: nil,
            clock: FixedClock(now),
            calendar: { calendar },
            makeNarrator: { nil }
        )
    }
}

struct SystemClock: Clock {
    var now: Date { Date() }
}
