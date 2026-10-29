import Foundation
import Testing

@testable import Vivra

/// End to end inside the host app: real Keychain, real SQLCipher, no
/// HealthKit. Keychain access needs an app's entitlements on the simulator,
/// so Keychain behaviour is tested here rather than in VivraStore's package
/// tests. Tests go through app code only (no package imports), so they don't
/// depend on package symbols the app's linker may have stripped.
@MainActor
@Suite(.serialized) struct AppModelTests {
    /// A fixed test-only service, so repeated runs reuse one Keychain item.
    private static let keychainService = "app.vivra.apptests.database-key"
    private static let now = Date(timeIntervalSince1970: 1_775_000_000)

    private struct Harness {
        let model: AppModel
        let directory: URL
        let suiteName: String

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults().removePersistentDomain(forName: suiteName)
        }
    }

    private static func makeHarness(directory: URL? = nil, suiteName: String? = nil, sampleData: Bool = false)
        -> Harness
    {
        let directory =
            directory
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(
                "AppModelTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let suiteName = suiteName ?? "app.vivra.apptests.\(UUID().uuidString)"
        let environment = AppEnvironment.isolated(
            directory: directory, keychainService: keychainService, now: now, sampleData: sampleData)
        let model = AppModel(
            environment: environment,
            defaults: UserDefaults(suiteName: suiteName)!,
            defaultsDomain: suiteName
        )
        return Harness(model: model, directory: directory, suiteName: suiteName)
    }

    @Test func firstLaunchOpensTheStoreAndShowsOnboarding() async {
        let harness = Self.makeHarness()
        defer { harness.cleanUp() }

        await harness.model.start()

        #expect(harness.model.phase == .onboarding)
    }

    /// A second launch must find the key the first one stored. If the key
    /// were regenerated, SQLCipher would refuse the existing file.
    @Test func secondLaunchReusesTheStoredKey() async {
        let first = Self.makeHarness()
        defer { first.cleanUp() }
        await first.model.start()

        let second = Self.makeHarness(directory: first.directory, suiteName: first.suiteName)
        await second.model.start()

        #expect(second.model.phase == .onboarding)
    }

    @Test func completingOnboardingShowsTheDashboardOnNextLaunch() async {
        let first = Self.makeHarness()
        defer { first.cleanUp() }
        await first.model.start()
        first.model.acceptDisclaimer()
        await first.model.completeOnboarding()
        #expect(first.model.phase == .ready)
        #expect(first.model.dashboard?.days.count == 7)

        let second = Self.makeHarness(directory: first.directory, suiteName: first.suiteName)
        await second.model.start()
        #expect(second.model.phase == .ready)
        #expect(second.model.preferences.hasAcceptedCurrentDisclaimer)
    }

    @Test func summaryWithoutDataUsesTheEmptyTemplate() async {
        let harness = Self.makeHarness()
        defer { harness.cleanUp() }
        await harness.model.start()
        await harness.model.completeOnboarding()

        await harness.model.createReport(.weekly)

        let report = harness.model.latestReport(.weekly)
        #expect(report?.summary.generator.rawValue == "template")
        #expect(report?.summary.draft.bullets.isEmpty == true)
        #expect(report?.createdAt == Self.now)
    }

    @Test func deleteEverythingLeavesNothingBehind() async {
        let harness = Self.makeHarness()
        defer { harness.cleanUp() }
        await harness.model.start()
        harness.model.acceptDisclaimer()
        await harness.model.completeOnboarding()
        await harness.model.createReport(.weekly)

        let report = await harness.model.deleteAllData()

        #expect(report == DeletionReport(databaseRemoved: true, keyRemoved: true, preferencesCleared: true))
        #expect(harness.model.phase == .deleted)
        #expect(!FileManager.default.fileExists(atPath: harness.directory.path))
        #expect(UserDefaults(suiteName: harness.suiteName)?.object(forKey: "onboardingCompleted") == nil)
        #expect(harness.model.latestReport(.weekly) == nil)
    }

    @Test func startingAgainAfterDeletingBeginsFresh() async {
        let harness = Self.makeHarness()
        defer { harness.cleanUp() }
        await harness.model.start()
        await harness.model.completeOnboarding()
        await harness.model.createReport(.weekly)
        _ = await harness.model.deleteAllData()

        await harness.model.start()

        #expect(harness.model.phase == .onboarding)
        #expect(harness.model.latestReport(.weekly) == nil)
    }

    @Test func quickLogSavesEveryFilledInEntryAndDeletesThem() async {
        let harness = Self.makeHarness()
        defer { harness.cleanUp() }
        await harness.model.start()
        await harness.model.completeOnboarding()

        var draft = QuickLogDraft()
        #expect(!(await harness.model.saveQuickLog(draft)))
        draft.mood = 4
        draft.drinks[.coffee] = 2
        draft.note = "  lunch outside  "
        #expect(await harness.model.saveQuickLog(draft))

        let logs = harness.model.todayLogs
        #expect(logs.count == 3)
        #expect(logs.contains { $0.kind.rawValue == "mood" && $0.scale == 4 })
        #expect(logs.contains { $0.kind.rawValue == "drink" && $0.amount == 190 })
        #expect(logs.contains { $0.note == "lunch outside" })
        #expect(harness.model.dashboard?.todayLogged[.mood] == 4)

        for entry in logs { await harness.model.deleteLog(entry) }
        #expect(harness.model.todayLogs.isEmpty)
    }

    @Test func exportWritesEveryTableAndCleanupRemovesIt() async throws {
        let harness = Self.makeHarness()
        defer { harness.cleanUp() }
        await harness.model.start()
        await harness.model.completeOnboarding()
        var draft = QuickLogDraft()
        draft.mood = 4
        draft.note = "lunch, \"outside\""
        #expect(await harness.model.saveQuickLog(draft))
        await harness.model.setGoal(2)
        await harness.model.createReport(.daily)

        let export = try #require(await harness.model.prepareExport())
        let fileManager = FileManager.default
        #expect(export.folder.lastPathComponent == "Vivra Export 2026-03-31")
        let names = Set(try fileManager.contentsOfDirectory(atPath: export.folder.path))
        #expect(names.count == 11)
        #expect(names.contains("vivra-export.json"))
        #expect(names.contains("logs.csv"))

        let data = try Data(contentsOf: export.folder.appendingPathComponent("vivra-export.json"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["formatVersion"] as? Int == 1)
        #expect((json["logs"] as? [Any])?.count == 2)
        #expect((json["reports"] as? [Any])?.count == 1)
        #expect((json["goals"] as? [Any])?.count == 1)
        for key in ["quantitySamples", "sleepIntervals", "workouts", "categoryEvents", "statesOfMind", "ecgRecords"] {
            #expect((json[key] as? [Any])?.isEmpty == true, "\(key)")
        }
        let logsCSV = try String(contentsOf: export.folder.appendingPathComponent("logs.csv"), encoding: .utf8)
        #expect(logsCSV.contains("\"lunch, \"\"outside\"\"\""))

        let archiveSize = try fileManager.attributesOfItem(atPath: export.archive.path)[.size] as? Int
        #expect((archiveSize ?? 0) > 0)
        // The simulator doesn't report Data Protection classes.
        #if !targetEnvironment(simulator)
            for url in [export.directory, export.archive, export.folder.appendingPathComponent("vivra-export.json")] {
                let protection =
                    try fileManager.attributesOfItem(atPath: url.path)[.protectionKey] as? FileProtectionType
                #expect(protection == .complete)
            }
        #endif

        harness.model.finishExport(export)
        #expect(!fileManager.fileExists(atPath: export.directory.path))
    }

    /// Debug builds can start with made-up data for screenshots; every
    /// screen should then have something to show.
    @Test func sampleDataFillsEveryScreen() async {
        let harness = Self.makeHarness(sampleData: true)
        defer { harness.cleanUp() }
        await harness.model.start()
        await harness.model.completeOnboarding()

        let dashboard = harness.model.dashboard
        #expect(dashboard?.sleep.isEmpty == false)
        #expect(dashboard?.heart.isEmpty == false)
        #expect(dashboard?.workouts.isEmpty == false)
        #expect((harness.model.progress?.totalDaysLogged ?? 0) > 60)
        #expect(harness.model.history(.restingHeartRate)?.points.isEmpty == false)

        await harness.model.createReport(.weekly)
        #expect(harness.model.latestReport(.weekly)?.summary.draft.bullets.isEmpty == false)
    }

    /// Connections makes the same checks as the Patterns list, so a found
    /// connection is exactly a listed pattern (PLAN Phase 7).
    @Test func connectionsMatchThePatternsList() async throws {
        let harness = Self.makeHarness(sampleData: true)
        defer { harness.cleanUp() }
        await harness.model.start()
        await harness.model.completeOnboarding()

        let board = try #require(harness.model.connections)
        #expect(board.rows.count == 17)
        let found = board.found.map(\.id).sorted()
        let patterns = harness.model.patterns.map(\.id).filter { $0.hasPrefix("pattern.") }.sorted()
        #expect(!found.isEmpty)
        #expect(found == patterns)
        let finding = try #require(board.found.first?.status.finding)
        #expect(harness.model.connectionDays(finding)?.pairs.isEmpty == false)
    }

    /// Research notes are picked in Swift and saved with the summary
    /// (PLAN Phase 8). Debug builds, like these tests, include draft cards.
    @Test func summariesCarryResearchNotesButFeelingOffDoesNot() async throws {
        let harness = Self.makeHarness(sampleData: true)
        defer { harness.cleanUp() }
        await harness.model.start()
        await harness.model.completeOnboarding()

        await harness.model.createReport(.weekly)
        let weekly = try #require(harness.model.latestReport(.weekly)?.summary)
        #expect(!weekly.notes.isEmpty)
        #expect(weekly.notes.count <= 3)
        for note in weekly.notes {
            #expect(weekly.findings.contains { $0.id == note.findingID })
            #expect(AppModel.evidence.card(id: note.cardID) != nil)
        }

        await harness.model.createReport(.feelingOff)
        #expect(harness.model.latestReport(.feelingOff)?.summary.notes.isEmpty == true)
    }

    /// The Daily Summary widget shows today's check-in, so its link opens
    /// Insights on Summaries rather than Connections.
    @Test func theWidgetLinkOpensSummaries() {
        let harness = Self.makeHarness()
        defer { harness.cleanUp() }
        #expect(harness.model.insightsSection == .connections)

        harness.model.open(InsightsLink.url)
        #expect(harness.model.insightsRequested)
        #expect(harness.model.insightsSection == .summaries)

        harness.model.open(QuickLogLink.url)
        #expect(harness.model.quickLogRequested)
    }

    @Test func dailyCheckInWithoutDataUsesTheEmptyTemplate() async {
        let harness = Self.makeHarness()
        defer { harness.cleanUp() }
        await harness.model.start()
        await harness.model.completeOnboarding()

        await harness.model.createReport(.daily)

        let report = harness.model.latestReport(.daily)
        #expect(report?.kind.rawValue == "daily")
        #expect(report?.summary.draft.headline == "Not enough data for a check-in yet")
        #expect(harness.model.latestReport(.weekly) == nil)
    }

    @Test func newUsersAreAskedForEveryGroupDuringOnboarding() async {
        let harness = Self.makeHarness()
        defer { harness.cleanUp() }
        await harness.model.start()
        #expect(harness.model.pendingPermissionGroups.count == 7)

        for group in harness.model.pendingPermissionGroups { harness.model.markRequested(group) }

        #expect(harness.model.pendingPermissionGroups.isEmpty)
    }

    @Test func phaseOneUsersAreAskedOnlyForWhatsNew() async {
        let first = Self.makeHarness()
        defer { first.cleanUp() }
        // Simulate a Phase 1 install: onboarding done, no revisions stored.
        UserDefaults(suiteName: first.suiteName)?.set(true, forKey: "onboardingCompleted")

        let upgraded = Self.makeHarness(directory: first.directory, suiteName: first.suiteName)

        #expect(
            upgraded.model.pendingPermissionGroups.map(\.rawValue) == [
                "heart", "activity", "mind", "nutrition", "body",
            ])
    }

    @Test func quickLogRequestsAreRouted() {
        let harness = Self.makeHarness()
        defer { harness.cleanUp() }
        harness.model.quickLogRequested = true
        #expect(QuickLogLink.url.absoluteString == "vivra://quick-log")
    }
}
