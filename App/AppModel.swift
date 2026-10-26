import Foundation
import HealthSync
import InsightEngine
import NarrativeCore
import Observation
import SyncCore
import VivraLogging
import VivraModel
import VivraStore

/// What "delete everything" removed, checked after the fact.
struct DeletionReport: Equatable {
    var databaseRemoved: Bool
    var keyRemoved: Bool
    var preferencesCleared: Bool

    var isComplete: Bool { databaseRemoved && keyRemoved && preferencesCleared }
}

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case starting
        /// The encrypted store couldn't be opened (for example, the device
        /// is locked during a background launch).
        case storeUnavailable
        case onboarding
        case ready
        /// Everything was deleted; nothing is recreated until the person
        /// chooses to start again.
        case deleted
    }

    private(set) var phase: Phase = .starting
    private(set) var dashboard: DashboardSnapshot?
    private(set) var latestReport: StoredReport?
    private(set) var isSyncing = false
    private(set) var lastSyncHadFailures = false
    private(set) var isCreatingSummary = false
    private(set) var lastDeletionReport: DeletionReport?

    let preferences: Preferences
    let lock: AppLock

    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private var database: VivraDatabase?
    @ObservationIgnored private var repository: HealthRepository?
    @ObservationIgnored private var syncEngine: SyncEngine?
    @ObservationIgnored private var startTask: Task<Void, Never>?

    init(environment: AppEnvironment, defaults: UserDefaults, defaultsDomain: String?) {
        self.environment = environment
        preferences = Preferences(defaults: defaults, domainName: defaultsDomain)
        lock = AppLock(preferences: preferences)
    }

    static func live() -> AppModel {
        AppModel(environment: .live, defaults: .standard, defaultsDomain: Bundle.main.bundleIdentifier)
    }

    var isHealthAvailable: Bool { environment.health != nil }

    // MARK: Launch

    /// Opens the encrypted store. Safe to call repeatedly and concurrently.
    func start() async {
        if let startTask { return await startTask.value }
        let task = Task { await performStart() }
        startTask = task
        await task.value
    }

    private func performStart() async {
        phase = .starting
        let storeDirectory = environment.storeDirectory
        let keyProvider = KeychainKeyProvider(service: environment.keychainService)
        do {
            let database = try await Task.detached(priority: .userInitiated) {
                try VivraDatabase.open(in: storeDirectory(), keyProvider: keyProvider)
            }.value
            let repository = HealthRepository(database: database)
            self.database = database
            self.repository = repository
            if let health = environment.health {
                syncEngine = SyncEngine(
                    source: health,
                    store: repository,
                    clock: environment.clock,
                    calendar: environment.calendar()
                )
            }
            latestReport = try? await repository.latestReport()
        } catch {
            Log.app.failure("Store open failed", code: (error as NSError).code)
            phase = .storeUnavailable
            // Allow a later retry (e.g. once the device is unlocked).
            startTask = nil
            return
        }

        if preferences.onboardingCompleted {
            phase = .ready
            await refreshDashboard()
            Task { await sync() }
        } else {
            phase = .onboarding
        }
    }

    // MARK: Onboarding

    func acceptDisclaimer() {
        preferences.acceptedDisclaimerVersion = Preferences.currentDisclaimerVersion
    }

    func requestPermission(_ group: PermissionGroup) async {
        do {
            try await environment.health?.requestAuthorization(for: group)
        } catch {
            Log.app.failure("Authorization request failed", code: (error as NSError).code)
        }
    }

    func completeOnboarding() async {
        preferences.onboardingCompleted = true
        phase = .ready
        startObservingHealth()
        await refreshDashboard()
        await sync()
    }

    // MARK: Sync

    /// Registers HealthKit observers with background delivery. Called at
    /// launch (from the app delegate) once onboarding is done.
    func startObservingHealth() {
        environment.health?.startObserving { [weak self] type in
            await self?.handleHealthChange(type)
        }
    }

    private func handleHealthChange(_ type: HealthDataType) async {
        await start()
        guard phase == .ready, let syncEngine else { return }
        _ = await syncEngine.sync([type])
        await refreshDashboard()
    }

    func sync() async {
        guard phase == .ready, let syncEngine, !isSyncing else { return }
        isSyncing = true
        let report = await syncEngine.sync()
        lastSyncHadFailures = !report.failures.isEmpty
        isSyncing = false
        await refreshDashboard()
    }

    func refreshDashboard() async {
        guard let repository else { return }
        let calendar = environment.calendar()
        let clock = environment.clock
        let range = DashboardSnapshot.loadRange(clock: clock, calendar: calendar)
        do {
            async let samples = repository.quantitySamples(
                [.restingHeartRate, .heartRateVariabilitySDNN],
                from: range.start,
                to: range.end
            )
            async let sleep = repository.sleepIntervals(endingFrom: range.start, to: range.end)
            async let workouts = repository.workouts(from: range.start, to: range.end)
            dashboard = DashboardSnapshot.build(
                sleepIntervals: try await sleep,
                samples: try await samples,
                workouts: try await workouts,
                clock: clock,
                calendar: calendar
            )
        } catch {
            Log.app.failure("Dashboard load failed", code: (error as NSError).code)
        }
    }

    // MARK: Weekly summary

    func createWeeklySummary() async {
        guard let repository, !isCreatingSummary else { return }
        isCreatingSummary = true
        defer { isCreatingSummary = false }

        let calendar = environment.calendar()
        let clock = environment.clock
        let today = calendar.day(clock.now)
        let start = calendar.start(of: calendar.adding(days: -(PatternRules.patternWindowDays + 1), to: today))
        let end = calendar.start(of: today)
        do {
            async let samples = repository.quantitySamples(
                [.restingHeartRate, .heartRateVariabilitySDNN, .walkingHeartRateAverage, .vo2Max],
                from: start,
                to: end
            )
            async let sleep = repository.sleepIntervals(endingFrom: start, to: end)
            async let workouts = repository.workouts(from: start, to: end)
            let report = WeeklyReportBuilder.build(
                sleepIntervals: try await sleep,
                samples: try await samples,
                workouts: try await workouts,
                clock: clock,
                calendar: calendar,
                sourcePolicy: .default
            )
            let summary = await SummaryComposer.compose(report, narrator: environment.makeNarrator())
            let stored = StoredReport(
                periodStart: report.periodStart,
                periodEnd: report.periodEnd,
                createdAt: clock.now,
                summary: summary
            )
            try await repository.saveReport(stored)
            latestReport = stored
        } catch {
            Log.app.failure("Summary failed", code: (error as NSError).code)
        }
    }

    // MARK: Delete everything

    /// Stops sync, closes and deletes the database, deletes the Keychain key
    /// and clears preferences, then checks each one is really gone.
    func deleteAllData() async -> DeletionReport {
        await environment.health?.stopObserving()
        syncEngine = nil
        repository = nil
        if let database {
            do { try database.close() } catch {
                Log.app.failure("Database close failed", code: (error as NSError).code)
            }
        }
        database = nil
        startTask = nil
        dashboard = nil
        latestReport = nil

        let directory = try? environment.storeDirectory()
        if let directory {
            do { try VivraDatabase.destroy(in: directory) } catch {
                Log.app.failure("Database delete failed", code: (error as NSError).code)
            }
        }
        let keyProvider = KeychainKeyProvider(service: environment.keychainService)
        do { try keyProvider.deleteKey() } catch { Log.app.failure("Key delete failed", code: (error as NSError).code) }
        preferences.removeAll()
        lock.reset()

        let report = DeletionReport(
            databaseRemoved: directory.map { !FileManager.default.fileExists(atPath: $0.path) } ?? false,
            keyRemoved: (try? keyProvider.hasStoredKey()) == false,
            preferencesCleared: preferences.isEmpty
        )
        Log.app.event(report.isComplete ? "Delete everything complete" : "Delete everything incomplete")
        lastDeletionReport = report
        phase = .deleted
        return report
    }
}
