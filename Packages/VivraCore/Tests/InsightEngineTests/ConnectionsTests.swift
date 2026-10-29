import Foundation
import SyncCore
import Testing
import VivraModel

@testable import InsightEngine

@Suite struct ConnectionsTests {
    private func board(_ dataset: HealthDataset) -> ConnectionBoard {
        ConnectionBoard.build(dataset, clock: Fixtures.clock, calendar: Fixtures.utc, sourcePolicy: Fixtures.ownPolicy)
    }

    private func status(_ board: ConnectionBoard, _ id: String) throws -> ConnectionStatus {
        try #require(board.row(id: id)).status
    }

    /// The dataset the app would load from the store for sample data.
    private static func sampleDataset(seed: UInt64) -> HealthDataset {
        let data = SampleData.generate(now: Fixtures.now, calendar: Fixtures.utc, days: 90, seed: seed)
        let batches = data.batches.map(\.batch)
        let quantities = batches.flatMap(\.quantitySamples)
        return HealthDataset(
            sleepIntervals: batches.flatMap(\.sleepIntervals),
            samples: quantities.filter { HealthDataset.averageKinds.contains($0.kind) },
            dailySourceTotals: .totals(from: quantities, calendar: Fixtures.utc),
            workouts: batches.flatMap(\.workouts),
            logs: data.logs
        )
    }

    // MARK: Rows

    @Test func hasOneRowPerCheck() {
        let ids = board(Fixtures.dataset()).rows.map(\.id)
        let expected =
            ["pattern.shorterSleep.restingHeartRate", "pattern.workoutDay.sleepDuration"]
            + PatternCatalog.correlations.map(\.id)
        #expect(ids.count == 17)
        #expect(Set(ids) == Set(expected))
        #expect(Set(ids).count == ids.count)
    }

    /// A found row is exactly the pattern reports and the Patterns list show.
    @Test(arguments: [2026, 1, 2, 3] as [UInt64])
    func foundRowsArePatternListsPatterns(seed: UInt64) {
        let dataset = Self.sampleDataset(seed: seed)
        let board = board(dataset)
        let patterns = PatternList.build(
            dataset, clock: Fixtures.clock, calendar: Fixtures.utc, sourcePolicy: Fixtures.ownPolicy
        )
        .filter(\.detail.isPattern)
        let found = board.found.compactMap(\.status.finding)
        #expect(!found.isEmpty)
        #expect(found.sorted { $0.id < $1.id } == patterns.sorted { $0.id < $1.id })
    }

    @Test func orderIsDeterministicAndGroupedByOutcome() {
        let dataset = Self.sampleDataset(seed: 2026)
        let first = board(dataset)
        #expect(first == board(dataset))
        let positions = first.rows.map { ConnectionBoard.outcomeOrder.firstIndex(of: $0.outcome)! }
        #expect(positions == positions.sorted())
        // Within an outcome, found rows come first.
        for outcome in ConnectionBoard.outcomeOrder {
            let rows = first.rows(outcome: outcome)
            let foundFlags = rows.map { $0.status.finding != nil }
            #expect(foundFlags == foundFlags.sorted { $0 && !$1 })
        }
    }

    @Test func carriesEachOutcomesUsualRange() throws {
        let board = board(Self.sampleDataset(seed: 2026))
        let sleep = try #require(board.usual[.sleepDuration])
        #expect(sleep.axisLow <= sleep.low && sleep.low <= sleep.median)
        #expect(sleep.median <= sleep.high && sleep.high <= sleep.axisHigh)
        #expect(sleep.days >= 80)
    }

    // MARK: Statuses

    @Test func nothingRecorded() throws {
        let board = board(Fixtures.dataset())
        #expect(try status(board, "pattern.shorterSleep.restingHeartRate") == .notRecorded(.sleepDuration))
        #expect(try status(board, "pattern.workoutDay.sleepDuration") == .notRecorded(.workoutMinutes))
        #expect(try status(board, "pattern.caffeine.sleepDuration.lag1") == .notRecorded(.caffeine))
        #expect(board.found.isEmpty)
    }

    @Test func outcomeNotRecorded() throws {
        let logs = (1...30).map {
            Fixtures.log(.drink, day: Fixtures.daysAgo($0), drink: .coffee, amount: Double(50 * ($0 % 4)) + 10)
        }
        let board = board(Fixtures.dataset(logs: logs))
        #expect(try status(board, "pattern.caffeine.sleepDuration.lag1") == .notRecorded(.sleepDuration))
    }

    @Test func needsMoreDays() throws {
        var logs: [LogEntry] = []
        var sleep: [SleepInterval] = []
        for offset in 2...11 {
            logs.append(
                Fixtures.log(.drink, day: Fixtures.daysAgo(offset), drink: .coffee, amount: Double(offset * 20)))
            sleep.append(Fixtures.sleep(wakeDay: Fixtures.daysAgo(offset - 1), hours: 7))
        }
        let board = board(Fixtures.dataset(sleep: sleep, logs: logs))
        #expect(try status(board, "pattern.caffeine.sleepDuration.lag1") == .needsMoreDays(have: 10, need: 14))
    }

    /// The same amount every day: no two groups to compare.
    @Test func notEnoughVarietyInACorrelation() throws {
        var logs: [LogEntry] = []
        var sleep: [SleepInterval] = []
        for offset in 2...41 {
            logs.append(Fixtures.log(.drink, day: Fixtures.daysAgo(offset), drink: .coffee, amount: 100))
            sleep.append(Fixtures.sleep(wakeDay: Fixtures.daysAgo(offset - 1), hours: 6 + Double(offset % 5) * 0.4))
        }
        let board = board(Fixtures.dataset(sleep: sleep, logs: logs))
        #expect(try status(board, "pattern.caffeine.sleepDuration.lag1") == .notEnoughVariety(days: 40))
    }

    /// A workout almost every day: too few days without one.
    @Test func notEnoughVarietyInAGroupDifference() throws {
        var sleep: [SleepInterval] = []
        var workouts: [Workout] = []
        for offset in 1...40 {
            sleep.append(Fixtures.sleep(wakeDay: Fixtures.daysAgo(offset), hours: 7 + Double(offset % 3) * 0.3))
            if offset % 10 != 0 { workouts.append(Fixtures.workout(day: Fixtures.daysAgo(offset), minutes: 30)) }
        }
        let board = board(Fixtures.dataset(sleep: sleep, workouts: workouts))
        guard case .notEnoughVariety = try status(board, "pattern.workoutDay.sleepDuration") else {
            Issue.record("Expected not enough variety")
            return
        }
    }

    /// Unrelated data is tested, and shows nothing clear (ρ below the gate).
    @Test func noClearPatternInUnrelatedData() throws {
        var logs: [LogEntry] = []
        var sleep: [SleepInterval] = []
        for offset in 1...60 {
            logs.append(Fixtures.log(.mood, day: Fixtures.daysAgo(offset), scale: 1 + (offset * 7) % 5))
            sleep.append(Fixtures.sleep(wakeDay: Fixtures.daysAgo(offset), hours: 6 + Double((offset * 3) % 4) * 0.5))
        }
        let board = board(Fixtures.dataset(sleep: sleep, logs: logs))
        #expect(try status(board, "pattern.sleepDuration.mood.lag0") == .noClearPattern(days: 60))
    }

    /// A strong correlation whose groups differ by less than the minimum
    /// effect (15 minutes of sleep) is tested, then dropped after the
    /// correction.
    @Test func noClearPatternWhenTheDifferenceIsTiny() throws {
        var logs: [LogEntry] = []
        var sleep: [SleepInterval] = []
        for offset in 2...61 {
            let caffeine = Double((offset * 37) % 300)
            logs.append(Fixtures.log(.drink, day: Fixtures.daysAgo(offset), drink: .coffee, amount: caffeine + 1))
            sleep.append(Fixtures.sleep(wakeDay: Fixtures.daysAgo(offset - 1), hours: 7 - caffeine / 30_000))
        }
        let board = board(Fixtures.dataset(sleep: sleep, logs: logs))
        #expect(try status(board, "pattern.caffeine.sleepDuration.lag1") == .noClearPattern(days: 60))
    }

    // MARK: Latest value

    /// Lag 1: yesterday's caffeine, the night that followed it being last night.
    @Test func latestForALagOneConnection() throws {
        var logs: [LogEntry] = []
        var sleep: [SleepInterval] = []
        for offset in 1...61 {
            let caffeine = offset == 1 ? 299 : Double((offset * 37) % 300)
            logs.append(Fixtures.log(.drink, day: Fixtures.daysAgo(offset), drink: .coffee, amount: caffeine + 1))
            let hours = 8 - caffeine / 200 + Double(offset % 3) * 0.1
            sleep.append(Fixtures.sleep(wakeDay: Fixtures.daysAgo(offset - 1), hours: hours))
        }
        let row = try #require(
            board(Fixtures.dataset(sleep: sleep, logs: logs)).row(id: "pattern.caffeine.sleepDuration.lag1"))
        #expect(row.status.finding != nil)
        let latest = try #require(row.latest)
        #expect(latest.daysAgo == 1)
        #expect(latest.value == 300)
        #expect(latest.side == .more)
    }

    /// Lag 0: last night's sleep and today's mood.
    @Test func latestForALagZeroConnection() throws {
        var logs: [LogEntry] = []
        var sleep: [SleepInterval] = []
        for offset in 0...60 {
            let hours = offset == 0 ? 5.0 : 5 + Double((offset * 7) % 30) / 10
            sleep.append(Fixtures.sleep(wakeDay: Fixtures.daysAgo(offset), hours: hours))
            if offset > 0 {
                logs.append(Fixtures.log(.mood, day: Fixtures.daysAgo(offset), scale: hours >= 6.5 ? 4 : 2))
            }
        }
        let row = try #require(
            board(Fixtures.dataset(sleep: sleep, logs: logs)).row(id: "pattern.sleepDuration.mood.lag0"))
        #expect(row.status.finding != nil)
        let latest = try #require(row.latest)
        #expect(latest.daysAgo == 0)
        #expect(latest.value == 5 * 3600)
        #expect(latest.side == .less)
        #expect(row.comparison.map { $0.moreMedian > $0.lessMedian } == true)
    }

    // MARK: Days

    /// Every found connection's days split into exactly the finding's groups.
    @Test(arguments: [2026, 1, 2, 3] as [UInt64])
    func daysMatchTheFinding(seed: UInt64) throws {
        let dataset = Self.sampleDataset(seed: seed)
        for row in board(dataset).found {
            let finding = try #require(row.status.finding)
            let days = try #require(
                ConnectionDays.build(
                    finding, dataset: dataset, clock: Fixtures.clock, calendar: Fixtures.utc,
                    sourcePolicy: Fixtures.ownPolicy))
            let comparison = try #require(row.comparison)
            let less = days.pairs(in: .less).map(\.outcome)
            let more = days.pairs(in: .more).map(\.outcome)
            #expect(less.count == comparison.lessDays, "\(row.id)")
            #expect(more.count == comparison.moreDays, "\(row.id)")
            #expect(Statistics.median(less) == comparison.lessMedian, "\(row.id)")
            #expect(Statistics.median(more) == comparison.moreMedian, "\(row.id)")
            #expect(days.timeline.count == ConnectionDays.timelineDays)
            #expect(days.timeline.map(\.day) == days.timeline.map(\.day).sorted())
        }
    }
}
