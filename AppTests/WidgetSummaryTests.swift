import Foundation
import Synchronization
import Testing

@testable import Vivra

/// The Daily Summary widget's file and the automatic daily check-in (PLAN
/// Phase 6). A temporary directory stands in for the App Group container,
/// and a flag for whether the widget is installed.
@MainActor
@Suite(.serialized) struct WidgetSummaryTests {
    private static let keychainService = "app.vivra.apptests.widget-key"
    /// 2026-03-31, 23:33 UTC.
    private static let now = Date(timeIntervalSince1970: 1_775_000_000)

    private final class WidgetState: Sendable {
        let installed = Mutex(true)
        let reloads = Mutex(0)
    }

    private struct Harness {
        let model: AppModel
        let directory: URL
        let widgetDirectory: URL
        let suiteName: String
        let widget: WidgetState

        var file: URL { widgetDirectory.appendingPathComponent("widget-summary.json") }

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: widgetDirectory)
            UserDefaults().removePersistentDomain(forName: suiteName)
        }
    }

    private static func makeHarness(now: Date = now, reusing other: Harness? = nil) -> Harness {
        let directory =
            other?.directory
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("WidgetTests-\(UUID().uuidString)")
        let widgetDirectory =
            other?.widgetDirectory
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("WidgetGroup-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: widgetDirectory, withIntermediateDirectories: true)
        let suiteName = other?.suiteName ?? "app.vivra.apptests.widget.\(UUID().uuidString)"
        let widget = other?.widget ?? WidgetState()
        let publisher = WidgetSummaryPublisher(
            directory: { widgetDirectory },
            isWidgetInstalled: { widget.installed.withLock { $0 } },
            reloadWidget: { widget.reloads.withLock { $0 += 1 } }
        )
        let environment = AppEnvironment.isolated(
            directory: directory, keychainService: keychainService, now: now, sampleData: other == nil,
            widgetSummary: publisher)
        let model = AppModel(
            environment: environment, defaults: UserDefaults(suiteName: suiteName)!, defaultsDomain: suiteName)
        return Harness(
            model: model, directory: directory, widgetDirectory: widgetDirectory, suiteName: suiteName, widget: widget)
    }

    private func readSummary(_ harness: Harness) throws -> WidgetSummary? {
        guard FileManager.default.fileExists(atPath: harness.file.path) else { return nil }
        return try JSONDecoder().decode(WidgetSummary.self, from: Data(contentsOf: harness.file))
    }

    @Test func writesTodaysCheckInOnlyWhileTheWidgetIsInstalled() async throws {
        let harness = Self.makeHarness()
        defer { harness.cleanUp() }
        await harness.model.start()
        await harness.model.completeOnboarding()

        await harness.model.ensureDailyCheckIn()

        let report = try #require(harness.model.latestReport(.daily))
        let summary = try #require(try readSummary(harness))
        #expect(summary.day == "2026-03-31")
        #expect(summary.headline == report.summary.draft.headline)
        #expect(summary.sentences == Array(report.summary.draft.bullets.prefix(2).map(\.text)))
        #expect(summary.sentences.count == 2)
        #expect(!summary.writtenByModel)
        #expect(harness.widget.reloads.withLock { $0 } >= 1)
        #if !targetEnvironment(simulator)
            let protection = try FileManager.default.attributesOfItem(atPath: harness.file.path)[.protectionKey]
            #expect(protection as? FileProtectionType == .completeUntilFirstUserAuthentication)
        #endif

        // Removing the widget removes the file the next time Vivra checks.
        harness.widget.installed.withLock { $0 = false }
        await harness.model.publishWidgetSummary()
        #expect(!FileManager.default.fileExists(atPath: harness.file.path))
    }

    @Test func neverWritesWhenTheWidgetIsntInstalled() async {
        let harness = Self.makeHarness()
        defer { harness.cleanUp() }
        harness.widget.installed.withLock { $0 = false }
        await harness.model.start()
        await harness.model.completeOnboarding()

        await harness.model.ensureDailyCheckIn()

        #expect(harness.model.latestReport(.daily) != nil)
        #expect(!FileManager.default.fileExists(atPath: harness.file.path))
    }

    @Test func deleteEverythingRemovesTheWidgetFile() async {
        let harness = Self.makeHarness()
        defer { harness.cleanUp() }
        await harness.model.start()
        await harness.model.completeOnboarding()
        await harness.model.ensureDailyCheckIn()
        #expect(FileManager.default.fileExists(atPath: harness.file.path))

        _ = await harness.model.deleteAllData()

        #expect(!FileManager.default.fileExists(atPath: harness.file.path))
    }

    /// Once per day: a later launch the same day keeps the morning's
    /// check-in, and the next day gets a new one.
    @Test func makesOneCheckInPerDay() async throws {
        let first = Self.makeHarness()
        defer { first.cleanUp() }
        await first.model.start()
        await first.model.completeOnboarding()
        await first.model.ensureDailyCheckIn()
        let morning = try #require(first.model.latestReport(.daily))
        #expect(morning.createdAt == Self.now)

        let later = Self.makeHarness(now: Self.now.addingTimeInterval(20 * 60), reusing: first)
        await later.model.start()
        await later.model.ensureDailyCheckIn()
        #expect(later.model.latestReport(.daily)?.createdAt == Self.now)

        let nextDay = Self.makeHarness(now: Self.now.addingTimeInterval(24 * 3600), reusing: first)
        await nextDay.model.start()
        await nextDay.model.ensureDailyCheckIn()
        let tomorrow = try #require(nextDay.model.latestReport(.daily))
        #expect(tomorrow.createdAt == Self.now.addingTimeInterval(24 * 3600))
        #expect(try readSummary(nextDay)?.day == "2026-04-01")
    }

    @Test func aStaleCheckInIsntShownOnTheWidget() async throws {
        let first = Self.makeHarness()
        defer { first.cleanUp() }
        await first.model.start()
        await first.model.completeOnboarding()
        await first.model.ensureDailyCheckIn()
        #expect(try readSummary(first)?.day == "2026-03-31")

        // The next day, before a new check-in is made, the old file goes.
        let nextDay = Self.makeHarness(now: Self.now.addingTimeInterval(24 * 3600), reusing: first)
        await nextDay.model.start()
        await nextDay.model.publishWidgetSummary()
        #expect(try readSummary(nextDay) == nil)
    }
}
