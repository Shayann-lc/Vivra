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

/// What Quick Log collects on one screen. Everything is optional; Save
/// stores whatever was filled in, all at one timestamp.
struct QuickLogDraft: Equatable {
    var mood: Int?
    var energy: Int?
    var stress: Int?
    /// Servings per drink.
    var drinks: [Drink: Int] = [:]
    var meal = false
    var note = ""

    var isEmpty: Bool {
        mood == nil && energy == nil && stress == nil && drinks.values.allSatisfy { $0 == 0 } && !meal
            && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func entries(at timestamp: Date) -> [LogEntry] {
        var entries: [LogEntry] = []
        if let mood { entries.append(LogEntry(kind: .mood, timestamp: timestamp, scale: mood)) }
        if let energy { entries.append(LogEntry(kind: .energy, timestamp: timestamp, scale: energy)) }
        if let stress { entries.append(LogEntry(kind: .stress, timestamp: timestamp, scale: stress)) }
        for drink in Drink.allCases {
            guard let servings = drinks[drink], servings > 0 else { continue }
            entries.append(
                LogEntry(
                    kind: .drink,
                    timestamp: timestamp,
                    drink: drink,
                    amount: Double(servings) * drink.amountPerServing
                )
            )
        }
        if meal { entries.append(LogEntry(kind: .meal, timestamp: timestamp)) }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { entries.append(LogEntry(kind: .note, timestamp: timestamp, note: trimmed)) }
        return entries
    }
}

/// ECG recordings and irregular rhythm notifications, listed as Apple Health
/// recorded them.
struct HeartRecordings: Equatable {
    var ecgs: [ECGRecord] = []
    var irregularRhythmDates: [Date] = []

    static let lookbackDays = 90
    var isEmpty: Bool { ecgs.isEmpty && irregularRhythmDates.isEmpty }
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
    private(set) var heartRecordings = HeartRecordings()
    private(set) var latestReports: [ReportKind: StoredReport] = [:]
    private(set) var creatingReport: ReportKind?
    private(set) var patterns: [Finding] = []
    private(set) var todayLogs: [LogEntry] = []
    private(set) var isSyncing = false
    private(set) var lastSyncHadFailures = false
    private(set) var lastDeletionReport: DeletionReport?
    /// Set when a widget, control or shortcut asks for Quick Log.
    var quickLogRequested = false

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
        // People who finished onboarding before Phase 2 were asked for the
        // Phase 1 groups.
        if preferences.onboardingCompleted && preferences.requestedPermissionRevisions.isEmpty {
            preferences.requestedPermissionRevisions = Dictionary(
                uniqueKeysWithValues: PermissionGroup.phaseOneRevisions.map { ($0.key.rawValue, $0.value) }
            )
        }
    }

    static func live() -> AppModel {
        AppModel(environment: .live, defaults: .standard, defaultsDomain: Bundle.main.bundleIdentifier)
    }

    var isHealthAvailable: Bool { environment.health != nil }

    /// Reports and the model leave Strava workouts out (PLAN §8); the
    /// dashboard shows every source. Both ignore Vivra's own written samples.
    private var reportPolicy: SourcePolicy { .default.withOwnBundleIdentifier(environment.ownBundleIdentifier) }
    private var dashboardPolicy: SourcePolicy { .includeAll.withOwnBundleIdentifier(environment.ownBundleIdentifier) }

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
            for kind in [ReportKind.daily, .weekly] {
                latestReports[kind] = try? await repository.latestReport(kind: kind)
            }
        } catch {
            Log.app.failure("Store open failed", code: (error as NSError).code)
            phase = .storeUnavailable
            // Allow a later retry (e.g. once the device is unlocked).
            startTask = nil
            return
        }

        if preferences.onboardingCompleted {
            phase = .ready
            await refresh()
            Task { await sync() }
        } else {
            phase = .onboarding
        }
    }

    // MARK: Onboarding and permissions

    func acceptDisclaimer() {
        preferences.acceptedDisclaimerVersion = Preferences.currentDisclaimerVersion
    }

    /// Groups not yet asked for at their current revision.
    var pendingPermissionGroups: [PermissionGroup] {
        let requested = Dictionary(
            uniqueKeysWithValues: preferences.requestedPermissionRevisions.compactMap { key, value in
                PermissionGroup(rawValue: key).map { ($0, value) }
            }
        )
        return PermissionGroup.pending(requested: requested)
    }

    func requestPermission(_ group: PermissionGroup) async {
        do {
            try await environment.health?.requestAuthorization(for: group)
        } catch {
            Log.app.failure("Authorization request failed", code: (error as NSError).code)
        }
        markRequested(group)
    }

    /// Records that the person saw the group, whether they allowed it or not.
    func markRequested(_ group: PermissionGroup) {
        preferences.requestedPermissionRevisions[group.rawValue] = group.revision
    }

    func completeOnboarding() async {
        preferences.onboardingCompleted = true
        phase = .ready
        startObservingHealth()
        await refresh()
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
        await refresh()
    }

    /// Reloads everything shown on screen.
    func refresh() async {
        await refreshDashboard()
        await refreshTodayLogs()
        await refreshPatterns()
    }

    func refreshDashboard() async {
        guard let repository else { return }
        let calendar = environment.calendar()
        let clock = environment.clock
        let days = DashboardSnapshot.loadDays(clock: clock, calendar: calendar)
        do {
            let dataset = try await repository.dataset(first: days.first, last: days.last, calendar: calendar)
            dashboard = DashboardSnapshot.build(
                dataset, clock: clock, calendar: calendar, sourcePolicy: dashboardPolicy)

            let from = calendar.start(of: calendar.adding(days: -HeartRecordings.lookbackDays, to: days.last))
            let to = calendar.start(of: calendar.adding(days: 1, to: days.last))
            async let ecgs = repository.ecgRecords(from: from, to: to)
            async let irregular = repository.categoryEvents([.irregularRhythm], from: from, to: to)
            heartRecordings = HeartRecordings(
                ecgs: try await ecgs,
                irregularRhythmDates: try await irregular.map(\.start).sorted(by: >)
            )
        } catch {
            Log.app.failure("Dashboard load failed", code: (error as NSError).code)
        }
    }

    private func analysisDataset() async throws -> HealthDataset? {
        guard let repository else { return nil }
        let calendar = environment.calendar()
        let today = calendar.day(environment.clock.now)
        // 90 complete days for patterns, a day more for lags, and today for
        // the daily check-in.
        return try await repository.dataset(
            first: calendar.adding(days: -(PatternRules.patternWindowDays + 1), to: today),
            last: today,
            calendar: calendar
        )
    }

    func refreshPatterns() async {
        do {
            guard let dataset = try await analysisDataset() else { return }
            patterns = PatternList.build(
                dataset,
                clock: environment.clock,
                calendar: environment.calendar(),
                sourcePolicy: reportPolicy
            )
        } catch {
            Log.app.failure("Pattern load failed", code: (error as NSError).code)
        }
    }

    // MARK: Reports

    func latestReport(_ kind: ReportKind) -> StoredReport? { latestReports[kind] }

    func createReport(_ kind: ReportKind) async {
        guard let repository, creatingReport == nil else { return }
        creatingReport = kind
        defer { creatingReport = nil }
        let calendar = environment.calendar()
        let clock = environment.clock
        do {
            guard let dataset = try await analysisDataset() else { return }
            let report: InsightReport =
                switch kind {
                case .weekly:
                    WeeklyReportBuilder.build(dataset, clock: clock, calendar: calendar, sourcePolicy: reportPolicy)
                case .daily:
                    DailyCheckInBuilder.build(dataset, clock: clock, calendar: calendar, sourcePolicy: reportPolicy)
                }
            let summary = await SummaryComposer.compose(report, narrator: environment.makeNarrator())
            let stored = StoredReport(
                kind: kind,
                periodStart: report.periodStart,
                periodEnd: report.periodEnd,
                createdAt: clock.now,
                summary: summary
            )
            try await repository.saveReport(stored)
            latestReports[kind] = stored
        } catch {
            Log.app.failure("Report failed", code: (error as NSError).code)
        }
    }

    // MARK: Quick Log

    func refreshTodayLogs() async {
        guard let repository else { return }
        let calendar = environment.calendar()
        let today = calendar.day(environment.clock.now)
        do {
            todayLogs = try await repository.logs(
                from: calendar.start(of: today),
                to: calendar.start(of: calendar.adding(days: 1, to: today))
            )
        } catch {
            Log.app.failure("Log load failed", code: (error as NSError).code)
        }
    }

    /// Saves every filled-in entry. With write-back on, mood and drinks are
    /// also written to Apple Health; a failed write keeps the entry in Vivra.
    @discardableResult
    func saveQuickLog(_ draft: QuickLogDraft) async -> Bool {
        guard let repository, !draft.isEmpty else { return false }
        let timestamp = environment.clock.now
        do {
            for var entry in draft.entries(at: timestamp) {
                if preferences.writeBackEnabled, let health = environment.health, let write = HealthWrite.for(entry),
                    health.canWrite(write.dataType)
                {
                    do {
                        entry = entry.with(healthKitSampleID: try await health.save(write, at: timestamp))
                    } catch {
                        Log.app.failure("Write-back failed", code: (error as NSError).code)
                    }
                }
                try await repository.saveLog(entry)
            }
            Log.app.event("Quick log saved")
            await refreshTodayLogs()
            await refreshDashboard()
            return true
        } catch {
            Log.app.failure("Quick log save failed", code: (error as NSError).code)
            return false
        }
    }

    /// Deletes an entry, and the sample it wrote to Apple Health if any.
    func deleteLog(_ entry: LogEntry) async {
        guard let repository else { return }
        if let sampleID = entry.healthKitSampleID, let write = HealthWrite.for(entry) {
            do {
                try await environment.health?.deleteSample(id: sampleID, of: write.dataType)
            } catch {
                Log.app.failure("Write-back delete failed", code: (error as NSError).code)
            }
        }
        do {
            try await repository.deleteLog(id: entry.id)
        } catch {
            Log.app.failure("Log delete failed", code: (error as NSError).code)
        }
        await refreshTodayLogs()
        await refreshDashboard()
    }

    /// Turning write-back on asks for write permission first.
    func setWriteBack(_ enabled: Bool) async {
        if enabled, let health = environment.health {
            do {
                try await health.requestWriteAuthorization()
            } catch {
                Log.app.failure("Write authorization failed", code: (error as NSError).code)
                return
            }
        }
        preferences.writeBackEnabled = enabled
    }

    // MARK: Delete everything

    /// Stops sync, closes and deletes the database, deletes the Keychain key
    /// and clears preferences, then checks each one is really gone. Samples
    /// Vivra wrote to Apple Health stay there: they belong to the person's
    /// Health data now, and the Health app can delete them.
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
        heartRecordings = HeartRecordings()
        latestReports = [:]
        patterns = []
        todayLogs = []

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
