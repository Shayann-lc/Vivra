import Foundation
import NarrativeCore
import Testing
import VivraModel

@testable import Gamification

private let utc = DayCalendar(timeZone: TimeZone(identifier: "UTC")!)
private let today = Day(year: 2026, month: 4, day: 30)
/// 10:00 on `today`.
private let now = utc.start(of: today).addingTimeInterval(10 * 3600)

private func daysAgo(_ n: Int) -> Day { utc.adding(days: -n, to: today) }

/// One check-in (one save) on each day `n` days ago, at `hour`.
private func checkIns(_ offsets: [Int], hour: Double = 9, kind: LogEntry.Kind = .mood) -> [LogEntry] {
    offsets.map {
        LogEntry(kind: kind, timestamp: utc.start(of: daysAgo($0)).addingTimeInterval(hour * 3600), scale: 3)
    }
}

private func build(
    _ logs: [LogEntry],
    goals: [GoalChange] = [],
    events: [AppEvent] = [],
    at clock: Date = now
) -> ProgressSnapshot {
    ProgressEngine.build(logs: logs, goals: goals, events: events, clock: FixedClock(clock), calendar: utc)
}

private func unlocked(_ snapshot: ProgressSnapshot, _ achievement: Achievement) -> Day? {
    snapshot.achievements.first { $0.achievement == achievement }?.unlockedOn
}

@Suite struct RunTests {
    @Test func nothingLoggedYet() {
        let snapshot = build([])
        #expect(snapshot.currentRun == 0)
        #expect(snapshot.totalDaysLogged == 0)
        #expect(snapshot.xp == 0)
        #expect(snapshot.level == 1)
        #expect(snapshot.lastSevenDays.last?.status == .inProgress)
        #expect(snapshot.lastSevenDays.first?.status == .notStarted)
    }

    @Test func consecutiveDaysBuildARunAndTodayIsNotMissedYet() {
        let snapshot = build(checkIns([3, 2, 1]))
        #expect(snapshot.currentRun == 3)
        #expect(snapshot.lastSevenDays.last?.status == .inProgress)
        #expect(!snapshot.goalMetToday)
        #expect(ProgressCopy.goal(snapshot) == "Today: 0 of 1 check-in")
    }

    @Test func aMissedDayWithoutPausesStartsANewRunButKeepsTotals() {
        let snapshot = build(checkIns([5, 4, 2, 1, 0]))
        #expect(snapshot.currentRun == 3)
        #expect(snapshot.longestRun == 3)
        #expect(snapshot.totalDaysLogged == 5)
        #expect(snapshot.lastSevenDays.first { $0.day == daysAgo(3) }?.status == .missed)
    }

    @Test func sevenGoalDaysEarnAPauseThatCoversTheNextMiss() {
        // Days 10…4 met (7 days), day 3 missed, days 2…0 met.
        let snapshot = build(checkIns(Array((4...10).reversed()) + [2, 1, 0]))
        #expect(snapshot.lastSevenDays.first { $0.day == daysAgo(3) }?.status == .paused)
        #expect(snapshot.currentRun == 10)
        #expect(snapshot.pausesHeld == 0)
    }

    @Test func pausesAreCappedAtTwo() {
        let snapshot = build(checkIns(Array((0...27).reversed())))
        #expect(snapshot.currentRun == 28)
        #expect(snapshot.pausesHeld == ProgressRules.maximumPauses)
    }

    @Test func backfillingYesterdayRepairsTheRun() {
        let before = build(checkIns([3, 2, 0]))
        #expect(before.currentRun == 1)
        let after = build(checkIns([3, 2, 0]) + checkIns([1], hour: 21))
        #expect(after.currentRun == 4)
    }

    @Test func aHigherGoalOnlyAppliesFromItsDay() {
        // Goal 2 from yesterday. Days before keep goal 1.
        let goals = [GoalChange(effective: daysAgo(1), target: 2)]
        let logs = checkIns([3, 2, 1]) + checkIns([1, 0], hour: 15) + checkIns([0], hour: 8)
        let snapshot = build(logs, goals: goals)
        #expect(snapshot.target == 2)
        #expect(snapshot.lastSevenDays.first { $0.day == daysAgo(2) }?.status == .met)
        #expect(snapshot.lastSevenDays.first { $0.day == daysAgo(1) }?.status == .met)
        #expect(snapshot.goalMetToday)
        #expect(snapshot.currentRun == 4)
        #expect(ProgressCopy.goal(snapshot) == "Today's goal done")
    }

    @Test func entriesSavedTogetherAreOneCheckIn() {
        let time = utc.start(of: today).addingTimeInterval(8 * 3600)
        let logs = [
            LogEntry(kind: .mood, timestamp: time, scale: 4),
            LogEntry(kind: .drink, timestamp: time, drink: .water, amount: 250),
        ]
        let snapshot = build(logs, goals: [GoalChange(effective: today, target: 2)])
        #expect(snapshot.checkInsToday == 1)
        #expect(!snapshot.goalMetToday)
    }

    @Test func welcomeBackAfterABreak() {
        let back = build(checkIns([6, 5, 0]))
        #expect(back.isWelcomeBack)
        #expect(ProgressCopy.saved(back, xpEarned: 15) == "Welcome back · +15 XP")
        #expect(unlocked(back, .comeback) == today)

        let shortGap = build(checkIns([2, 0]))
        #expect(!shortGap.isWelcomeBack)
    }
}

@Suite struct XPTests {
    @Test func xpRewardsLoggingVarietyUpToACap() {
        let time = utc.start(of: today).addingTimeInterval(8 * 3600)
        let kinds: [LogEntry.Kind] = [.mood, .energy, .stress, .drink, .meal, .note]
        let logs = kinds.map { LogEntry(kind: $0, timestamp: time) }
        let snapshot = build(logs)
        // 10 + 5 × 5 = 35, capped at 30, plus 5 for the goal.
        #expect(snapshot.xpToday == 35)
        #expect(snapshot.xp == 35)
        #expect(unlocked(snapshot, .everyKind) == today)
    }

    @Test func levelsFollowTheTable() {
        #expect(ProgressRules.levelStart(1) == 0)
        #expect(ProgressRules.levelStart(2) == 50)
        #expect(ProgressRules.levelStart(3) == 150)
        #expect(ProgressRules.levelStart(5) == 500)
        #expect(ProgressRules.level(forXP: 49) == 1)
        #expect(ProgressRules.level(forXP: 50) == 2)
        #expect(ProgressRules.level(forXP: 499) == 4)
        let snapshot = build(checkIns(Array((0...9).reversed())))
        #expect(snapshot.xp == 150)
        #expect(snapshot.level == 3)
        #expect(snapshot.levelStartXP == 150)
        #expect(snapshot.nextLevelXP == 300)
    }
}

@Suite struct AchievementTests {
    @Test func consistencyAchievementsUnlockOnTheDayTheyAreReached() {
        let snapshot = build(checkIns(Array((0...29).reversed())))
        #expect(unlocked(snapshot, .firstCheckIn) == daysAgo(29))
        #expect(unlocked(snapshot, .threeDays) == daysAgo(27))
        #expect(unlocked(snapshot, .weekRun) == daysAgo(23))
        #expect(unlocked(snapshot, .monthRun) == today)
        #expect(unlocked(snapshot, .hundredDays) == nil)
    }

    @Test func exploringAchievementsComeFromEvents() {
        let events = [
            AppEvent(kind: .viewedPatterns, date: utc.start(of: daysAgo(2))),
            AppEvent(kind: .viewedPatterns, date: utc.start(of: daysAgo(5))),
            AppEvent(kind: .enabledHealthSaving, date: now),
        ]
        let snapshot = build([], events: events)
        #expect(unlocked(snapshot, .patternSpotter) == daysAgo(5))
        #expect(unlocked(snapshot, .sharedWithHealth) == today)
        #expect(unlocked(snapshot, .firstWeeklySummary) == nil)
    }

    @Test func noAchievementRewardsExercise() {
        for achievement in Achievement.allCases {
            #expect(!achievement.detail.lowercased().contains("workout"))
            #expect(!achievement.detail.lowercased().contains("steps"))
        }
    }
}

@Suite struct ReminderTests {
    @Test func schedulesOnePerDayForAWeek() {
        let plan = ReminderPlan.plan(minutes: 19 * 60, goalMetToday: false, clock: FixedClock(now), calendar: utc)
        #expect(plan.count == 7)
        #expect(plan.first?.day == today)
        #expect(plan.first?.fireDate == utc.start(of: today).addingTimeInterval(19 * 3600))
        #expect(Set(plan.map(\.identifier)).count == 7)
    }

    @Test func skipsTodayOnceTheGoalIsMetOrTheTimeHasPassed() {
        let met = ReminderPlan.plan(minutes: 19 * 60, goalMetToday: true, clock: FixedClock(now), calendar: utc)
        #expect(met.count == 6)
        #expect(met.first?.day == utc.adding(days: 1, to: today))
        let early = ReminderPlan.plan(minutes: 8 * 60, goalMetToday: false, clock: FixedClock(now), calendar: utc)
        #expect(early.first?.day == utc.adding(days: 1, to: today))
    }

    @Test func messagesAreStablePerDay() {
        #expect(ReminderPlan.message(for: today) == ReminderPlan.message(for: today))
        let week = (0..<6).map { ReminderPlan.message(for: utc.adding(days: $0, to: today)) }
        #expect(Set(week).count == ReminderPlan.messages.count)
    }
}

@Suite struct CopyTests {
    private var samples: [String] {
        let snapshots = [build([]), build(checkIns([6, 5, 0])), build(checkIns(Array((0...9).reversed())))]
        return ProgressCopy.fixedStrings
            + snapshots.flatMap { [ProgressCopy.goal($0), ProgressCopy.run($0), ProgressCopy.saved($0, xpEarned: 15)] }
    }

    @Test func progressCopyFollowsTheStyleGuide() {
        for text in samples {
            for term in StyleGuide.bannedTerms + StyleGuide.causalPhrases {
                #expect(!NarrativeValidator.containsPhrase(term, in: text), "\"\(term)\" in \"\(text)\"")
            }
        }
    }

    @Test func progressCopyNeverTalksAboutLoss() {
        for text in samples {
            for phrase in ProgressCopy.lossPhrases {
                #expect(!text.lowercased().contains(phrase), "\"\(phrase)\" in \"\(text)\"")
            }
        }
    }

    @Test func remindersCarryNoNumbers() {
        for message in ReminderPlan.messages {
            #expect(NumberTokens.extract(from: message).isEmpty)
        }
    }
}
