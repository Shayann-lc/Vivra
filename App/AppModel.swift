import Foundation
import Gamification
import HealthSync
import InsightEngine
import NarrativeCore
import Norms
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
    /// Nil logs "now". Otherwise earlier today or yesterday
    /// (`AppModel.backfillRange`).
    var timestamp: Date?

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

/// Which published reference tables to compare with. App-level so views and
/// tests don't depend on package types.
enum ComparisonChoice: String, CaseIterable, Identifiable {
    case none
    case women
    case men

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: String(localized: "Don't compare")
        case .women: String(localized: "Women's reference data")
        case .men: String(localized: "Men's reference data")
        }
    }

    var group: ReferenceGroup? {
        switch self {
        case .none: nil
        case .women: .women
        case .men: .men
        }
    }
}

/// One comparison with published data, ready to show with its citation.
struct ReferenceLine: Equatable, Identifiable {
    let text: String
    let sourceName: String
    let citation: String
    let url: String
    let caveat: String
    var id: String { text }
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
    private(set) var progress: ProgressSnapshot?
    private(set) var glance: TodayGlance?
    private(set) var comparisonChoice = ComparisonChoice.none
    private(set) var birthYear: Int?
    private(set) var isExporting = false
    /// Shown briefly after a Quick Log save.
    var saveMessage: String?
    /// Offer a daily reminder (once, after the first save).
    var offerReminder = false
    /// Set when a widget, control or shortcut asks for Quick Log.
    var quickLogRequested = false
    /// Set when the Daily Summary widget is tapped; the tab view opens Insights.
    var insightsRequested = false

    let preferences: Preferences
    let lock: AppLock

    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private var database: VivraDatabase?
    @ObservationIgnored private var repository: HealthRepository?
    @ObservationIgnored private var syncEngine: SyncEngine?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    /// The last 90+ days, loaded once per refresh and shared by patterns, the
    /// glance and metric detail.
    @ObservationIgnored private var analysisCache: HealthDataset?
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?

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

    /// The live model, or in a Debug build launched by the UI tests, one with
    /// fresh storage and preferences.
    static func forLaunch(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppModel {
        #if DEBUG
            if arguments.contains(AppEnvironment.uiTestingArgument) {
                let suiteName = "app.vivra.uitesting"
                UserDefaults().removePersistentDomain(forName: suiteName)
                if let defaults = UserDefaults(suiteName: suiteName) {
                    let environment = AppEnvironment.uiTesting(
                        sampleData: arguments.contains(AppEnvironment.sampleDataArgument))
                    return AppModel(environment: environment, defaults: defaults, defaultsDomain: suiteName)
                }
            }
        #endif
        return live()
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
            #if DEBUG
                if environment.loadsSampleData { await loadSampleData(into: repository) }
            #endif
            if let health = environment.health {
                syncEngine = SyncEngine(
                    source: health,
                    store: repository,
                    clock: environment.clock,
                    calendar: environment.calendar()
                )
            }
            for kind in ReportKind.allCases {
                latestReports[kind] = try? await repository.latestReport(kind: kind)
            }
            await loadComparisonProfile()
        } catch {
            Log.app.failure("Store open failed", code: (error as NSError).code)
            phase = .storeUnavailable
            // Allow a later retry (e.g. once the device is unlocked).
            startTask = nil
            return
        }

        DataExporter.removeLeftovers(in: FileManager.default.temporaryDirectory)

        if preferences.onboardingCompleted {
            phase = .ready
            await refresh()
            Task { await sync() }
        } else {
            phase = .onboarding
        }
    }

    #if DEBUG
        /// Fills the store with `SampleData`. Only the UI tests' isolated
        /// stores and app tests ask for this.
        private func loadSampleData(into repository: HealthRepository) async {
            let data = SampleData.generate(now: environment.clock.now, calendar: environment.calendar())
            do {
                for (type, batch) in data.batches { try await repository.apply(batch, for: type) }
                for entry in data.logs { try await repository.saveLog(entry) }
                Log.app.event("Sample data loaded, logs", count: data.logs.count)
            } catch {
                Log.app.failure("Sample data failed", code: (error as NSError).code)
            }
        }
    #endif

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
        let hadPending = !pendingPermissionGroups.isEmpty
        preferences.requestedPermissionRevisions[group.rawValue] = group.revision
        if hadPending && pendingPermissionGroups.isEmpty {
            Task { await record(.answeredAllPermissions) }
        }
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
        scheduleDashboardRefresh()
    }

    /// Background deliveries often arrive for several types together. One
    /// refresh once they settle replaces one refresh per type. The data is
    /// already saved by then, and opening the app refreshes everything.
    private func scheduleDashboardRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: Self.refreshCoalescingDelay)
            guard !Task.isCancelled else { return }
            await self?.refreshDashboard()
        }
    }

    static let refreshCoalescingDelay = Duration.seconds(2)

    func sync() async {
        guard phase == .ready, let syncEngine, !isSyncing else { return }
        isSyncing = true
        let report = await Log.sync.measure("Sync all") { await syncEngine.sync() }
        lastSyncHadFailures = !report.failures.isEmpty
        isSyncing = false
        await refresh()
    }

    /// Reloads everything shown on screen.
    func refresh() async {
        pendingRefresh?.cancel()
        await Log.app.measure("Refresh") {
            await refreshDashboard()
            await refreshTodayLogs()
            await refreshAnalysis()
            await refreshProgress()
        }
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

    /// Reloads the analysis window and everything computed from it.
    func refreshAnalysis() async {
        do {
            guard let dataset = try await analysisDataset() else { return }
            analysisCache = dataset
            let clock = environment.clock
            let calendar = environment.calendar()
            await Log.insights.measure("Patterns and glance") {
                patterns = PatternList.build(dataset, clock: clock, calendar: calendar, sourcePolicy: reportPolicy)
                glance = TodayGlance.build(dataset, clock: clock, calendar: calendar, sourcePolicy: reportPolicy)
            }
        } catch {
            Log.app.failure("Analysis load failed", code: (error as NSError).code)
        }
    }

    /// The last 28 days of a metric, from the cached analysis window.
    func history(_ metric: Metric) -> MetricHistory? {
        guard let analysisCache else { return nil }
        return MetricHistory.build(
            metric,
            dataset: analysisCache,
            clock: environment.clock,
            calendar: environment.calendar(),
            sourcePolicy: dashboardPolicy
        )
    }

    func noteViewedPatterns() async {
        guard progress?.achievements.first(where: { $0.achievement == .patternSpotter })?.isUnlocked != true else {
            return
        }
        await record(.viewedPatterns)
    }

    // MARK: Reports

    func latestReport(_ kind: ReportKind) -> StoredReport? { latestReports[kind] }

    /// `automatic` is for the daily check-in Vivra makes on its own: it
    /// doesn't count as the person exploring Insights.
    func createReport(_ kind: ReportKind, automatic: Bool = false) async {
        guard let repository, creatingReport == nil else { return }
        creatingReport = kind
        defer { creatingReport = nil }
        let calendar = environment.calendar()
        let clock = environment.clock
        do {
            guard let dataset = try await analysisDataset() else { return }
            let report: InsightReport = await Log.insights.measure("Build report") {
                switch kind {
                case .weekly:
                    WeeklyReportBuilder.build(dataset, clock: clock, calendar: calendar, sourcePolicy: reportPolicy)
                case .daily:
                    DailyCheckInBuilder.build(dataset, clock: clock, calendar: calendar, sourcePolicy: reportPolicy)
                case .monthly:
                    MonthlyReportBuilder.build(dataset, clock: clock, calendar: calendar, sourcePolicy: reportPolicy)
                case .feelingOff:
                    FeelingOffBuilder.build(dataset, clock: clock, calendar: calendar, sourcePolicy: reportPolicy)
                }
            }
            let summary = await Log.narrative.measure("Compose summary") {
                await SummaryComposer.compose(report, narrator: environment.makeNarrator())
            }
            let stored = StoredReport(
                kind: kind,
                periodStart: report.periodStart,
                periodEnd: report.periodEnd,
                createdAt: clock.now,
                summary: summary
            )
            try await repository.saveReport(stored)
            latestReports[kind] = stored
            if kind == .daily { await publishWidgetSummary() }
            guard !automatic else { return }
            switch kind {
            case .weekly: await record(.createdWeeklySummary)
            case .daily: await record(.createdCheckIn)
            case .monthly, .feelingOff: break
            }
        } catch {
            Log.app.failure("Report failed", code: (error as NSError).code)
        }
    }

    // MARK: Daily check-in and widget

    /// Makes today's check-in if there isn't one yet, so Insights and the
    /// Daily Summary widget have it (PLAN Phase 6). Runs when the app
    /// becomes active and from the background task.
    func ensureDailyCheckIn() async {
        guard phase == .ready else { return }
        let today = environment.calendar().day(environment.clock.now)
        if latestReports[.daily]?.periodEnd == today {
            await publishWidgetSummary()
        } else {
            await createReport(.daily, automatic: true)
        }
    }

    /// Writes today's check-in for the widget, or removes the file when
    /// there's none for today or no widget is installed.
    func publishWidgetSummary() async {
        guard let publisher = environment.widgetSummary else { return }
        let today = environment.calendar().day(environment.clock.now)
        guard let daily = latestReports[.daily], daily.periodEnd == today else {
            await publisher.publish(nil)
            return
        }
        let draft = daily.summary.draft
        await publisher.publish(
            WidgetSummary(
                day: today.description,
                headline: draft.headline,
                sentences: WidgetText.sentences(from: draft),
                writtenByModel: daily.summary.generator == .onDeviceModel
            )
        )
    }

    /// The background refresh: opens the store (only possible while the
    /// device is unlocked), syncs and makes today's check-in.
    func runBackgroundCheckIn() async {
        await start()
        guard phase == .ready else { return }
        await sync()
        await ensureDailyCheckIn()
    }

    // MARK: Reference comparisons

    /// The bundled tables, plus FRIEND VO2 max medians in the owner's
    /// non-commercial build only (PLAN decision 10).
    var normTable: NormTable {
        #if VIVRA_NONCOMMERCIAL
            .bundled.merging(.friendMedians)
        #else
            .bundled
        #endif
    }

    private static let birthYearKey = "comparison.birthYear"
    private static let groupKey = "comparison.group"

    private func loadComparisonProfile() async {
        guard let repository else { return }
        let storedYear = try? await repository.setting(Self.birthYearKey)
        let storedGroup = try? await repository.setting(Self.groupKey)
        birthYear = storedYear.flatMap { Int($0) }
        comparisonChoice = storedGroup.flatMap { ComparisonChoice(rawValue: $0) } ?? .none
    }

    /// Stored in the encrypted database. Comparisons need both values.
    func setComparison(choice: ComparisonChoice, birthYear: Int?) async {
        guard let repository else { return }
        do {
            try await repository.setSetting(Self.groupKey, choice == .none ? nil : choice.rawValue)
            try await repository.setSetting(Self.birthYearKey, birthYear.map(String.init))
        } catch {
            Log.app.failure("Comparison save failed", code: (error as NSError).code)
        }
        await loadComparisonProfile()
    }

    var comparisonProfile: ComparisonProfile? {
        guard let birthYear, let group = comparisonChoice.group else { return nil }
        return ComparisonProfile(birthYear: birthYear, group: group)
    }

    /// Whether any reference data exists for `metric` in this build.
    func hasReferenceData(_ metric: Metric) -> Bool { normTable.metrics.contains(metric) }

    /// Comparisons for a metric's 28-day median (latest value for VO2 max),
    /// with citations. Empty when the profile isn't set or nothing applies.
    func references(for metric: Metric) -> [ReferenceLine] {
        guard let profile = comparisonProfile, let history = history(metric) else { return [] }
        let usesLatest = metric == .vo2Max
        guard let value = usesLatest ? history.points.last?.value : history.median else { return [] }
        let valueText = FindingFormatter.format(value, metric.unit)
        let subject = usesLatest ? "Your latest estimate" : "Your 28-day median"
        let year = environment.calendar().calendar.component(.year, from: environment.clock.now)
        return NormComparer.compare(metric, value: value, profile: profile, year: year, table: normTable).map {
            comparison in
            let subjectWithValue: String
            if case .percentile = comparison {
                subjectWithValue = "\(subject) of \(valueText)"
            } else {
                subjectWithValue = subject
            }
            return ReferenceLine(
                text: NormText.sentence(comparison, subject: subjectWithValue, valueText: valueText),
                sourceName: comparison.source.name,
                citation: comparison.source.citation,
                url: comparison.source.url,
                caveat: comparison.source.caveat
            )
        }
    }

    // MARK: Progress

    func refreshProgress() async {
        guard let repository else { return }
        do {
            async let logs = repository.allLogs()
            async let goals = repository.goalChanges()
            async let events = repository.events()
            progress = ProgressEngine.build(
                logs: try await logs,
                goals: try await goals,
                events: try await events,
                clock: environment.clock,
                calendar: environment.calendar()
            )
        } catch {
            Log.app.failure("Progress load failed", code: (error as NSError).code)
        }
        await scheduleReminders()
    }

    /// Sets the daily goal from today onwards; past days keep theirs.
    func setGoal(_ target: Int) async {
        guard let repository, ProgressRules.targetRange.contains(target) else { return }
        do {
            try await repository.setGoal(target, from: environment.calendar().day(environment.clock.now))
        } catch {
            Log.app.failure("Goal save failed", code: (error as NSError).code)
        }
        await refreshProgress()
    }

    private func record(_ kind: AppEventKind) async {
        guard let repository else { return }
        do {
            try await repository.recordEvent(AppEvent(kind: kind, date: environment.clock.now))
        } catch {
            Log.app.failure("Event save failed", code: (error as NSError).code)
        }
        await refreshProgress()
    }

    // MARK: Reminders

    func setReminders(enabled: Bool) async {
        if enabled {
            guard let reminders = environment.reminders, await reminders.authorize() else {
                preferences.remindersEnabled = false
                return
            }
        }
        preferences.remindersEnabled = enabled
        await scheduleReminders()
    }

    func setReminderTime(minutes: Int) async {
        preferences.reminderMinutes = min(max(minutes, 0), 24 * 60 - 1)
        await scheduleReminders()
    }

    func answerReminderOffer(accept: Bool) async {
        offerReminder = false
        preferences.reminderOffered = true
        if accept { await setReminders(enabled: true) }
    }

    /// Replaces pending reminders: none when off; otherwise one a day for a
    /// week, skipping today once its goal is met.
    private func scheduleReminders() async {
        guard let scheduler = environment.reminders else { return }
        guard preferences.remindersEnabled, phase == .ready else {
            await scheduler.replace(with: [])
            return
        }
        let plan = ReminderPlan.plan(
            minutes: preferences.reminderMinutes,
            goalMetToday: progress?.goalMetToday ?? false,
            clock: environment.clock,
            calendar: environment.calendar()
        )
        await scheduler.replace(
            with: plan.map {
                ScheduledReminder(
                    identifier: $0.identifier, fireDate: $0.fireDate, title: ReminderPlan.title, body: $0.message)
            }
        )
    }

    // MARK: Quick Log

    /// How far back Quick Log can log: from the start of yesterday until now.
    var backfillRange: ClosedRange<Date> {
        let calendar = environment.calendar()
        let now = environment.clock.now
        let earliest = calendar.start(of: calendar.adding(days: -ProgressRules.backfillDays, to: calendar.day(now)))
        return earliest...now
    }

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
        let range = backfillRange
        let timestamp = min(max(draft.timestamp ?? range.upperBound, range.lowerBound), range.upperBound)
        let xpBefore = progress?.xp ?? 0
        let wasFirstSave = (progress?.totalDaysLogged ?? 0) == 0
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
            await refreshProgress()
            if let progress {
                saveMessage = ProgressCopy.saved(progress, xpEarned: max(0, progress.xp - xpBefore))
            }
            if wasFirstSave && !preferences.reminderOffered && environment.reminders != nil {
                offerReminder = true
            }
            await refreshAnalysis()
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
        await refreshProgress()
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
        if enabled { await record(.enabledHealthSaving) }
    }

    // MARK: Export

    /// Writes every table as JSON and CSV into a protected temporary folder
    /// and zips it. Call `finishExport` once the share sheet closes.
    func prepareExport() async -> PreparedExport? {
        guard let repository, !isExporting else { return nil }
        isExporting = true
        defer { isExporting = false }
        let now = environment.clock.now
        let name = "Vivra Export \(environment.calendar().day(now).description)"
        let parent = FileManager.default.temporaryDirectory
        do {
            let bundle = try await repository.exportAll(at: now)
            let export = try await Task.detached(priority: .userInitiated) {
                try DataExporter.write(bundle.files(), name: name, in: parent)
            }.value
            Log.app.event("Export prepared")
            return export
        } catch {
            Log.app.failure("Export failed", code: (error as NSError).code)
            return nil
        }
    }

    func finishExport(_ export: PreparedExport) {
        DataExporter.cleanUp(export)
    }

    // MARK: Delete everything

    /// Stops sync, closes and deletes the database, deletes the Keychain key
    /// and clears preferences, then checks each one is really gone. Samples
    /// Vivra wrote to Apple Health stay there: they belong to the person's
    /// Health data now, and the Health app can delete them.
    func deleteAllData() async -> DeletionReport {
        await environment.health?.stopObserving()
        await environment.reminders?.replace(with: [])
        environment.widgetSummary?.remove()
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
        progress = nil
        glance = nil
        analysisCache = nil
        comparisonChoice = .none
        birthYear = nil

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
