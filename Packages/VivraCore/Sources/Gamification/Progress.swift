import Foundation
import VivraModel

/// Things people do in the app that unlock exploring achievements. Stored as
/// an append-only log; raw values are persisted, so never rename them.
public enum AppEventKind: String, Codable, Sendable, CaseIterable {
    case createdWeeklySummary
    case createdCheckIn
    case viewedPatterns
    case answeredAllPermissions
    case enabledHealthSaving
}

public struct AppEvent: Codable, Sendable, Hashable {
    public let kind: AppEventKind
    public let date: Date

    public init(kind: AppEventKind, date: Date) {
        self.kind = kind
        self.date = date
    }
}

/// The daily goal from `effective` onwards. Changing the goal adds a change,
/// so past days keep the goal they had.
public struct GoalChange: Codable, Sendable, Hashable {
    public let effective: Day
    public let target: Int

    public init(effective: Day, target: Int) {
        self.effective = effective
        self.target = target
    }
}

/// All the numbers, kept together so they're easy to review.
public enum ProgressRules {
    public static let defaultTarget = 1
    public static let targetRange = 1...3
    /// A pause is earned every this many goal days in a run...
    public static let pauseEvery = 7
    /// ...and at most this many are held.
    public static let maximumPauses = 2
    /// Quick Log can log this many days back (1: yesterday).
    public static let backfillDays = 1
    /// Days without a check-in that count as "a break" for Welcome back.
    public static let breakDays = 2
    public static let firstCheckInXP = 10
    public static let extraKindXP = 5
    public static let dailyLoggingXPCap = 30
    public static let goalMetXP = 5

    /// XP at which `level` starts: 0, 50, 150, 300, 500, …
    public static func levelStart(_ level: Int) -> Int { 25 * level * (level - 1) }

    public static func level(forXP xp: Int) -> Int {
        var level = 1
        while levelStart(level + 1) <= xp { level += 1 }
        return level
    }
}

public enum DayStatus: String, Sendable, Equatable {
    /// Before the first check-in.
    case notStarted
    case met
    /// A pause covered the day.
    case paused
    /// The goal wasn't met and no pause was left. Shown neutrally.
    case missed
    /// Today, goal not met yet.
    case inProgress
}

public struct DayProgress: Sendable, Equatable, Identifiable {
    public let day: Day
    public let status: DayStatus
    public let checkIns: Int
    public var id: Day { day }
}

public struct AchievementState: Sendable, Equatable, Identifiable {
    public let achievement: Achievement
    /// Nil while locked.
    public let unlockedOn: Day?
    public var id: Achievement { achievement }
    public var isUnlocked: Bool { unlockedOn != nil }
}

public struct ProgressSnapshot: Sendable, Equatable {
    public let today: Day
    public let target: Int
    public let checkInsToday: Int
    public let currentRun: Int
    public let longestRun: Int
    public let pausesHeld: Int
    public let totalDaysLogged: Int
    public let xp: Int
    public let xpToday: Int
    public let level: Int
    public let levelStartXP: Int
    public let nextLevelXP: Int
    /// The last 7 days, oldest first, ending today.
    public let lastSevenDays: [DayProgress]
    public let achievements: [AchievementState]
    /// Today is the first check-in after a break.
    public let isWelcomeBack: Bool

    public var goalMetToday: Bool { checkInsToday >= target }
}

public enum ProgressEngine {
    public static func build(
        logs: [LogEntry],
        goals: [GoalChange],
        events: [AppEvent],
        clock: any Clock,
        calendar: DayCalendar
    ) -> ProgressSnapshot {
        let today = calendar.day(clock.now)
        let sortedGoals = goals.sorted { $0.effective < $1.effective }
        func target(on day: Day) -> Int {
            let target = sortedGoals.last { $0.effective <= day }?.target ?? ProgressRules.defaultTarget
            return min(max(target, ProgressRules.targetRange.lowerBound), ProgressRules.targetRange.upperBound)
        }

        // A check-in is one Quick Log save: entries saved together share a timestamp.
        var saves: [Day: Set<Date>] = [:]
        var kinds: [Day: Set<LogEntry.Kind>] = [:]
        for log in logs {
            let day = calendar.day(log.timestamp)
            guard day <= today else { continue }
            saves[day, default: []].insert(log.timestamp)
            kinds[day, default: []].insert(log.kind)
        }
        let loggedDays = saves.keys.sorted()

        var statuses: [Day: DayStatus] = [:]
        var run = 0
        var longest = 0
        var goalDaysSincePause = 0
        var pauses = 0
        var xp = 0
        var xpToday = 0
        var runReached: [Int: Day] = [:]

        if let first = loggedDays.first {
            var day = first
            while day <= today {
                let checkIns = saves[day]?.count ?? 0
                let met = checkIns >= target(on: day)
                var dayXP = 0
                if checkIns > 0 {
                    let extraKinds = (kinds[day]?.count ?? 1) - 1
                    dayXP = min(
                        ProgressRules.dailyLoggingXPCap,
                        ProgressRules.firstCheckInXP + ProgressRules.extraKindXP * extraKinds
                    )
                }
                if met {
                    dayXP += ProgressRules.goalMetXP
                    run += 1
                    goalDaysSincePause += 1
                    if goalDaysSincePause == ProgressRules.pauseEvery {
                        goalDaysSincePause = 0
                        pauses = min(pauses + 1, ProgressRules.maximumPauses)
                    }
                    statuses[day] = .met
                    for milestone in [7, 30] where run == milestone && runReached[milestone] == nil {
                        runReached[milestone] = day
                    }
                } else if day == today {
                    statuses[day] = .inProgress
                } else if pauses > 0 {
                    pauses -= 1
                    statuses[day] = .paused
                } else {
                    run = 0
                    goalDaysSincePause = 0
                    statuses[day] = .missed
                }
                longest = max(longest, run)
                xp += dayXP
                if day == today { xpToday = dayXP }
                day = calendar.adding(days: 1, to: day)
            }
        }

        let lastSevenDays = (0..<7).reversed().map { offset -> DayProgress in
            let day = calendar.adding(days: -offset, to: today)
            let status = statuses[day] ?? (day == today ? .inProgress : .notStarted)
            return DayProgress(day: day, status: status, checkIns: saves[day]?.count ?? 0)
        }

        let level = ProgressRules.level(forXP: xp)
        let achievements = Achievement.allCases.map { achievement in
            AchievementState(
                achievement: achievement,
                unlockedOn: unlockDay(
                    achievement,
                    loggedDays: loggedDays,
                    kinds: kinds,
                    runReached: runReached,
                    events: events,
                    calendar: calendar
                )
            )
        }

        return ProgressSnapshot(
            today: today,
            target: target(on: today),
            checkInsToday: saves[today]?.count ?? 0,
            currentRun: run,
            longestRun: longest,
            pausesHeld: pauses,
            totalDaysLogged: loggedDays.count,
            xp: xp,
            xpToday: xpToday,
            level: level,
            levelStartXP: ProgressRules.levelStart(level),
            nextLevelXP: ProgressRules.levelStart(level + 1),
            lastSevenDays: lastSevenDays,
            achievements: achievements,
            isWelcomeBack: loggedDays.last == today && returnsAfterBreak(at: loggedDays.count - 1, loggedDays, calendar)
        )
    }

    /// Whether the logged day at `index` follows at least
    /// `ProgressRules.breakDays` days without a check-in.
    static func returnsAfterBreak(at index: Int, _ loggedDays: [Day], _ calendar: DayCalendar) -> Bool {
        guard index > 0 else { return false }
        let resumeAfter = calendar.adding(days: ProgressRules.breakDays + 1, to: loggedDays[index - 1])
        return loggedDays[index] >= resumeAfter
    }

    private static func unlockDay(
        _ achievement: Achievement,
        loggedDays: [Day],
        kinds: [Day: Set<LogEntry.Kind>],
        runReached: [Int: Day],
        events: [AppEvent],
        calendar: DayCalendar
    ) -> Day? {
        func nthLoggedDay(_ n: Int) -> Day? { loggedDays.count >= n ? loggedDays[n - 1] : nil }
        func firstEvent(_ kind: AppEventKind) -> Day? {
            events.filter { $0.kind == kind }.map { calendar.day($0.date) }.min()
        }
        switch achievement {
        case .firstCheckIn: return nthLoggedDay(1)
        case .threeDays: return nthLoggedDay(3)
        case .sevenDays: return nthLoggedDay(7)
        case .thirtyDays: return nthLoggedDay(30)
        case .hundredDays: return nthLoggedDay(100)
        case .weekRun: return runReached[7]
        case .monthRun: return runReached[30]
        case .comeback:
            return loggedDays.indices.first { returnsAfterBreak(at: $0, loggedDays, calendar) }.map { loggedDays[$0] }
        case .everyKind:
            var seen: Set<LogEntry.Kind> = []
            for day in loggedDays {
                seen.formUnion(kinds[day] ?? [])
                if seen.count == LogEntry.Kind.allCases.count { return day }
            }
            return nil
        case .firstWeeklySummary: return firstEvent(.createdWeeklySummary)
        case .firstCheckInReport: return firstEvent(.createdCheckIn)
        case .patternSpotter: return firstEvent(.viewedPatterns)
        case .allConnected: return firstEvent(.answeredAllPermissions)
        case .sharedWithHealth: return firstEvent(.enabledHealthSaving)
        }
    }
}
