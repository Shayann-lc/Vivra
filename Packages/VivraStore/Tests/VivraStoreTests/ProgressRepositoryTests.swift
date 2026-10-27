import Foundation
import Gamification
import Testing
import VivraModel

@testable import VivraStore

@Suite struct ProgressRepositoryTests {
    private func makeRepository() throws -> (HealthRepository, URL) {
        let directory = try makeTemporaryDirectory()
        let database = try VivraDatabase.open(in: directory, keyProvider: StaticKeyProvider(key: makeKey(13)))
        return (HealthRepository(database: database), directory)
    }

    @Test func goalChangesKeepHistoryAndReplaceSameDay() async throws {
        let (repository, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = Day(year: 2026, month: 4, day: 1)
        let second = Day(year: 2026, month: 4, day: 9)

        try await repository.setGoal(2, from: first)
        try await repository.setGoal(3, from: second)
        try await repository.setGoal(1, from: second)

        #expect(
            try await repository.goalChanges() == [
                GoalChange(effective: first, target: 2), GoalChange(effective: second, target: 1),
            ]
        )
    }

    @Test func eventsAreAppendedInOrder() async throws {
        let (repository, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        let later = AppEvent(kind: .viewedPatterns, date: Date(timeIntervalSince1970: 1_775_100_000))
        let earlier = AppEvent(kind: .createdCheckIn, date: Date(timeIntervalSince1970: 1_775_000_000))

        try await repository.recordEvent(later)
        try await repository.recordEvent(earlier)
        try await repository.recordEvent(later)

        #expect(try await repository.events() == [earlier, later, later])
    }

    @Test func allLogsAreOldestFirst() async throws {
        let (repository, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        let newer = LogEntry(kind: .mood, timestamp: Date(timeIntervalSince1970: 1_775_100_000), scale: 4)
        let older = LogEntry(kind: .meal, timestamp: Date(timeIntervalSince1970: 1_775_000_000))
        try await repository.saveLog(newer)
        try await repository.saveLog(older)

        #expect(try await repository.allLogs() == [older, newer])
    }

    @Test func settingsSetReplaceAndRemove() async throws {
        let (repository, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(try await repository.setting("comparison.birthYear") == nil)
        try await repository.setSetting("comparison.birthYear", "1984")
        try await repository.setSetting("comparison.birthYear", "1985")
        #expect(try await repository.setting("comparison.birthYear") == "1985")
        try await repository.setSetting("comparison.birthYear", nil)
        #expect(try await repository.setting("comparison.birthYear") == nil)
    }
}
