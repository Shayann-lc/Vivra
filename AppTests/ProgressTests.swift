import Foundation
import Testing

@testable import Vivra

/// Records what would be scheduled, in app types only.
private actor RecordingReminders: ReminderScheduling {
    private(set) var last: [ScheduledReminder]?
    private(set) var authorizations = 0

    func authorize() async -> Bool {
        authorizations += 1
        return true
    }

    func replace(with reminders: [ScheduledReminder]) async {
        last = reminders
    }
}

@MainActor
@Suite(.serialized) struct ProgressTests {
    private static let keychainService = "app.vivra.apptests.database-key"
    /// 2026-03-31 23:33:20 UTC.
    private static let now = Date(timeIntervalSince1970: 1_775_000_000)

    private struct Harness {
        let model: AppModel
        let reminders: RecordingReminders
        let directory: URL
        let suiteName: String

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults().removePersistentDomain(forName: suiteName)
        }
    }

    private static func makeReadyHarness() async -> Harness {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProgressTests-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "app.vivra.progresstests.\(UUID().uuidString)"
        let reminders = RecordingReminders()
        let model = AppModel(
            environment: .isolated(
                directory: directory, keychainService: keychainService, now: now, reminders: reminders),
            defaults: UserDefaults(suiteName: suiteName)!,
            defaultsDomain: suiteName
        )
        await model.start()
        await model.completeOnboarding()
        return Harness(model: model, reminders: reminders, directory: directory, suiteName: suiteName)
    }

    private func moodDraft(at timestamp: Date? = nil) -> QuickLogDraft {
        var draft = QuickLogDraft()
        draft.mood = 3
        draft.timestamp = timestamp
        return draft
    }

    @Test func loggingForYesterdayCountsTowardsTheRun() async {
        let harness = await Self.makeReadyHarness()
        defer { harness.cleanUp() }
        let yesterdayNoon = Self.now.addingTimeInterval(-(23.5 + 12) * 3600)

        await harness.model.saveQuickLog(moodDraft(at: yesterdayNoon))
        await harness.model.saveQuickLog(moodDraft())

        #expect(harness.model.progress?.currentRun == 2)
        #expect(harness.model.progress?.totalDaysLogged == 2)
        #expect(harness.model.saveMessage?.contains("2-day run") == true)
    }

    @Test func timesBeforeYesterdayAreClampedToTheRange() async {
        let harness = await Self.makeReadyHarness()
        defer { harness.cleanUp() }
        let range = harness.model.backfillRange

        await harness.model.saveQuickLog(moodDraft(at: Self.now.addingTimeInterval(-10 * 86_400)))

        let saved = harness.model.todayLogs
        #expect(saved.isEmpty)  // clamped to the start of yesterday, so not "today"
        #expect(harness.model.progress?.totalDaysLogged == 1)
        #expect(range.lowerBound < range.upperBound)
    }

    @Test func goalChangesApplyFromToday() async {
        let harness = await Self.makeReadyHarness()
        defer { harness.cleanUp() }
        await harness.model.saveQuickLog(moodDraft())
        #expect(harness.model.progress?.goalMetToday == true)

        await harness.model.setGoal(2)

        #expect(harness.model.progress?.target == 2)
        #expect(harness.model.progress?.goalMetToday == false)
    }

    @Test func creatingReportsUnlocksExploringAchievements() async {
        let harness = await Self.makeReadyHarness()
        defer { harness.cleanUp() }

        await harness.model.createReport(.weekly)
        await harness.model.noteViewedPatterns()

        let unlocked = harness.model.progress?.achievements.filter(\.isUnlocked).map(\.achievement.title) ?? []
        #expect(unlocked.contains("First weekly summary"))
        #expect(unlocked.contains("Pattern spotter"))
    }

    @Test func remindersSkipTodayOnceLoggedAndClearOnDelete() async {
        let harness = await Self.makeReadyHarness()
        defer { harness.cleanUp() }
        await harness.model.setReminderTime(minutes: 23 * 60 + 50)

        await harness.model.setReminders(enabled: true)
        #expect(await harness.reminders.authorizations == 1)
        #expect(await harness.reminders.last?.count == 7)

        await harness.model.saveQuickLog(moodDraft())
        #expect(await harness.reminders.last?.count == 6)
        #expect(await harness.reminders.last?.allSatisfy { $0.title == "Vivra" && !$0.body.isEmpty } == true)

        _ = await harness.model.deleteAllData()
        #expect(await harness.reminders.last?.isEmpty == true)
    }

    @Test func theReminderOfferAppearsOnceAfterTheFirstSave() async {
        let harness = await Self.makeReadyHarness()
        defer { harness.cleanUp() }

        await harness.model.saveQuickLog(moodDraft())
        #expect(harness.model.offerReminder)
        await harness.model.answerReminderOffer(accept: false)

        await harness.model.saveQuickLog(moodDraft())
        #expect(!harness.model.offerReminder)
        #expect(harness.model.preferences.reminderOffered)
        #expect(!harness.model.preferences.remindersEnabled)
    }

    @Test func todayCardsCanBeHiddenAndReordered() async {
        let harness = await Self.makeReadyHarness()
        defer { harness.cleanUp() }
        let preferences = harness.model.preferences

        preferences.hiddenTodayCards.insert(.body)
        preferences.todayCardOrder.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)

        let reloaded = Preferences(defaults: UserDefaults(suiteName: harness.suiteName)!, domainName: harness.suiteName)
        #expect(reloaded.visibleTodayCards == [.workouts, .sleep, .heart, .activity, .logged])
        #expect(TodayCard.ordered(["heart", "unknown"]) == [.heart, .sleep, .activity, .workouts, .logged, .body])
    }
}
