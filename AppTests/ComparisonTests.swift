import Foundation
import Testing

@testable import Vivra

@MainActor
@Suite(.serialized) struct ComparisonTests {
    private static let keychainService = "app.vivra.apptests.database-key"
    /// 2026-03-31 23:33:20 UTC.
    private static let now = Date(timeIntervalSince1970: 1_775_000_000)

    private static func makeReadyModel() async -> (AppModel, URL, String) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ComparisonTests-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "app.vivra.comparisontests.\(UUID().uuidString)"
        let model = AppModel(
            environment: .isolated(directory: directory, keychainService: keychainService, now: now),
            defaults: UserDefaults(suiteName: suiteName)!,
            defaultsDomain: suiteName
        )
        await model.start()
        await model.completeOnboarding()
        return (model, directory, suiteName)
    }

    private static func cleanUp(_ directory: URL, _ suiteName: String) {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    @Test func comparisonProfileIsStoredInTheDatabase() async {
        let (model, directory, suiteName) = await Self.makeReadyModel()
        defer { Self.cleanUp(directory, suiteName) }
        #expect(model.comparisonProfile == nil)

        await model.setComparison(choice: .men, birthYear: 1980)

        let reopened = AppModel(
            environment: .isolated(directory: directory, keychainService: Self.keychainService, now: Self.now),
            defaults: UserDefaults(suiteName: suiteName)!,
            defaultsDomain: suiteName
        )
        await reopened.start()
        #expect(reopened.comparisonChoice == .men)
        #expect(reopened.birthYear == 1980)
        #expect(UserDefaults(suiteName: suiteName)?.object(forKey: "comparison.birthYear") == nil)

        await reopened.setComparison(choice: .none, birthYear: 1980)
        #expect(reopened.comparisonProfile == nil)
    }

    @Test func referencesNeedAProfileAndData() async {
        let (model, directory, suiteName) = await Self.makeReadyModel()
        defer { Self.cleanUp(directory, suiteName) }

        #expect(model.hasReferenceData(.restingHeartRate))
        #expect(model.hasReferenceData(.sleepDuration))
        #expect(model.references(for: .restingHeartRate).isEmpty)

        await model.setComparison(choice: .women, birthYear: 1990)
        // Still nothing: no resting heart rate data in this store.
        #expect(model.references(for: .restingHeartRate).isEmpty)
    }

    @Test func defaultBuildHasNoVO2MaxReferenceTable() async {
        let (model, directory, suiteName) = await Self.makeReadyModel()
        defer { Self.cleanUp(directory, suiteName) }
        #if !VIVRA_NONCOMMERCIAL
            #expect(!model.hasReferenceData(.vo2Max))
        #endif
    }

    @Test func monthlyAndFeelingOffReportsWithoutData() async {
        let (model, directory, suiteName) = await Self.makeReadyModel()
        defer { Self.cleanUp(directory, suiteName) }

        await model.createReport(.monthly)
        await model.createReport(.feelingOff)

        #expect(model.latestReport(.monthly)?.summary.draft.headline == "Not enough data for a monthly summary yet")
        #expect(model.latestReport(.feelingOff)?.summary.draft.headline == "Nothing stood out in today's data")
    }
}
