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
    /// Samples with this source were written by Vivra (write-back) and are
    /// ignored when read back.
    var ownBundleIdentifier: String?
    var reminders: (any ReminderScheduling)?

    static var live: AppEnvironment {
        AppEnvironment(
            storeDirectory: { try VivraDatabase.defaultDirectory() },
            keychainService: KeychainKeyProvider.defaultService,
            health: HealthKitDataSource.isHealthDataAvailable ? HealthKitDataSource() : nil,
            clock: SystemClock(),
            calendar: { DayCalendar(Calendar.autoupdatingCurrent) },
            makeNarrator: { FoundationModelsNarrator.isAvailable ? FoundationModelsNarrator() : nil },
            ownBundleIdentifier: Bundle.main.bundleIdentifier,
            reminders: NotificationReminderScheduler()
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
        timeZoneIdentifier: String = "UTC",
        reminders: (any ReminderScheduling)? = nil
    ) -> AppEnvironment {
        let calendar = DayCalendar(timeZone: TimeZone(identifier: timeZoneIdentifier) ?? .gmt)
        return AppEnvironment(
            storeDirectory: { directory },
            keychainService: keychainService,
            health: nil,
            clock: FixedClock(now),
            calendar: { calendar },
            makeNarrator: { nil },
            ownBundleIdentifier: "app.vivra.isolated",
            reminders: reminders
        )
    }
}

struct SystemClock: Clock {
    var now: Date { Date() }
}

#if DEBUG
    extension AppEnvironment {
        /// The launch argument UI tests pass.
        static let uiTestingArgument = "-ui-testing"

        /// For UI tests: fresh storage on every launch, no HealthKit prompts,
        /// no language model and no notifications. Debug builds only.
        static func uiTesting() -> AppEnvironment {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "UITesting", isDirectory: true)
            try? FileManager.default.removeItem(at: directory)
            return AppEnvironment(
                storeDirectory: { directory },
                keychainService: "app.vivra.uitesting.database-key",
                health: nil,
                clock: SystemClock(),
                calendar: { DayCalendar(Calendar.autoupdatingCurrent) },
                makeNarrator: { nil },
                ownBundleIdentifier: Bundle.main.bundleIdentifier,
                reminders: nil
            )
        }
    }
#endif
