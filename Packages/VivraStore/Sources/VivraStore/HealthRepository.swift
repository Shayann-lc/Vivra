import Foundation
import GRDB
import InsightEngine
import NarrativeCore
import SyncCore
import VivraLogging
import VivraModel

/// Reads and writes synced health data and reports.
public final class HealthRepository: SyncStore, Sendable {
    private let writer: any DatabaseWriter

    public init(database: VivraDatabase) {
        writer = database.writer
    }

    // MARK: SyncStore

    public func anchor(for type: HealthDataType) async throws -> Data? {
        try await writer.read { db in
            try Data.fetchOne(db, sql: "SELECT anchor FROM sync_anchor WHERE data_type = ?", arguments: [type.rawValue])
        }
    }

    public func apply(_ batch: ChangeBatch, for type: HealthDataType) async throws {
        // One transaction: objects, deletions and the anchor commit together.
        try await writer.write { db in
            for sample in batch.quantitySamples {
                try QuantitySampleRecord(sample).insert(db, onConflict: .replace)
            }
            for interval in batch.sleepIntervals {
                try SleepIntervalRecord(interval).insert(db, onConflict: .replace)
            }
            for workout in batch.workouts {
                try WorkoutRecord(workout).insert(db, onConflict: .replace)
            }
            if !batch.deletedIDs.isEmpty {
                let table: String =
                    switch type {
                    case .sleep: SleepIntervalRecord.databaseTableName
                    case .workouts: WorkoutRecord.databaseTableName
                    default: QuantitySampleRecord.databaseTableName
                    }
                for id in batch.deletedIDs {
                    try db.execute(sql: "DELETE FROM \(table) WHERE id = ?", arguments: [id.uuidString])
                }
            }
            try db.execute(
                sql: "INSERT OR REPLACE INTO sync_anchor (data_type, anchor) VALUES (?, ?)",
                arguments: [type.rawValue, batch.newAnchor]
            )
        }
    }

    // MARK: Reads

    /// Samples of `kinds` starting in `[from, to)`, oldest first.
    public func quantitySamples(_ kinds: [QuantityKind], from: Date, to: Date) async throws -> [QuantitySample] {
        try await writer.read { db in
            try QuantitySampleRecord
                .filter(kinds.map(\.rawValue).contains(Column("kind")))
                .filter(Column("start") >= from.timeIntervalSince1970 && Column("start") < to.timeIntervalSince1970)
                .order(Column("start"))
                .fetchAll(db)
                .compactMap(\.model)
        }
    }

    /// Sleep intervals ending in `[from, to)`, oldest first.
    public func sleepIntervals(endingFrom from: Date, to: Date) async throws -> [SleepInterval] {
        try await writer.read { db in
            try SleepIntervalRecord
                .filter(Column("end") >= from.timeIntervalSince1970 && Column("end") < to.timeIntervalSince1970)
                .order(Column("start"))
                .fetchAll(db)
                .compactMap(\.model)
        }
    }

    /// Workouts starting in `[from, to)`, newest first.
    public func workouts(from: Date, to: Date) async throws -> [Workout] {
        try await writer.read { db in
            try WorkoutRecord
                .filter(Column("start") >= from.timeIntervalSince1970 && Column("start") < to.timeIntervalSince1970)
                .order(Column("start").desc)
                .fetchAll(db)
                .map(\.model)
        }
    }

    // MARK: Reports

    public func saveReport(_ report: StoredReport) async throws {
        let record = try ReportRecord(report)
        try await writer.write { db in try record.insert(db) }
    }

    public func latestReport() async throws -> StoredReport? {
        try await writer.read { db in
            try ReportRecord.order(Column("id").desc).fetchOne(db)
        }
        .flatMap { try? $0.model() }
    }
}

/// A generated weekly summary, as saved.
public struct StoredReport: Sendable, Equatable {
    public let periodStart: Day
    public let periodEnd: Day
    public let createdAt: Date
    public let summary: ComposedSummary

    public init(periodStart: Day, periodEnd: Day, createdAt: Date, summary: ComposedSummary) {
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.createdAt = createdAt
        self.summary = summary
    }
}

// MARK: - Records

private struct QuantitySampleRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "quantity_sample"

    var id: String
    var kind: String
    var start: Double
    var end: Double
    var value: Double
    var sourceBundleID: String
    var sourceName: String

    enum CodingKeys: String, CodingKey {
        case id, kind, start, end, value
        case sourceBundleID = "source_bundle_id"
        case sourceName = "source_name"
    }

    init(_ sample: QuantitySample) {
        id = sample.id.uuidString
        kind = sample.kind.rawValue
        start = sample.start.timeIntervalSince1970
        end = sample.end.timeIntervalSince1970
        value = sample.value
        sourceBundleID = sample.source.bundleIdentifier
        sourceName = sample.source.name
    }

    var model: QuantitySample? {
        guard let uuid = UUID(uuidString: id), let kind = QuantityKind(rawValue: kind) else { return nil }
        return QuantitySample(
            id: uuid,
            kind: kind,
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: end),
            value: value,
            source: SourceInfo(bundleIdentifier: sourceBundleID, name: sourceName)
        )
    }
}

private struct SleepIntervalRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "sleep_interval"

    var id: String
    var stage: String
    var start: Double
    var end: Double
    var sourceBundleID: String
    var sourceName: String

    enum CodingKeys: String, CodingKey {
        case id, stage, start, end
        case sourceBundleID = "source_bundle_id"
        case sourceName = "source_name"
    }

    init(_ interval: SleepInterval) {
        id = interval.id.uuidString
        stage = interval.stage.rawValue
        start = interval.start.timeIntervalSince1970
        end = interval.end.timeIntervalSince1970
        sourceBundleID = interval.source.bundleIdentifier
        sourceName = interval.source.name
    }

    var model: SleepInterval? {
        guard let uuid = UUID(uuidString: id), let stage = SleepStage(rawValue: stage) else { return nil }
        return SleepInterval(
            id: uuid,
            stage: stage,
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: end),
            source: SourceInfo(bundleIdentifier: sourceBundleID, name: sourceName)
        )
    }
}

private struct WorkoutRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "workout"

    var id: String
    var activityType: Int64
    var start: Double
    var end: Double
    var duration: Double
    var activeEnergyKilocalories: Double?
    var distanceMeters: Double?
    var sourceBundleID: String
    var sourceName: String

    enum CodingKeys: String, CodingKey {
        case id, start, end, duration
        case activityType = "activity_type"
        case activeEnergyKilocalories = "active_energy_kcal"
        case distanceMeters = "distance_m"
        case sourceBundleID = "source_bundle_id"
        case sourceName = "source_name"
    }

    init(_ workout: Workout) {
        id = workout.id.uuidString
        activityType = Int64(workout.activityType)
        start = workout.start.timeIntervalSince1970
        end = workout.end.timeIntervalSince1970
        duration = workout.duration
        activeEnergyKilocalories = workout.activeEnergyKilocalories
        distanceMeters = workout.distanceMeters
        sourceBundleID = workout.source.bundleIdentifier
        sourceName = workout.source.name
    }

    var model: Workout {
        Workout(
            id: UUID(uuidString: id) ?? UUID(),
            activityType: UInt(activityType),
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: end),
            duration: duration,
            activeEnergyKilocalories: activeEnergyKilocalories,
            distanceMeters: distanceMeters,
            source: SourceInfo(bundleIdentifier: sourceBundleID, name: sourceName)
        )
    }
}

private struct ReportRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "report"

    var id: Int64?
    var periodStart: String
    var periodEnd: String
    var createdAt: Double
    var generator: String
    var summaryJSON: Data

    enum CodingKeys: String, CodingKey {
        case id, generator
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case createdAt = "created_at"
        case summaryJSON = "summary_json"
    }

    init(_ report: StoredReport) throws {
        id = nil
        periodStart = report.periodStart.description
        periodEnd = report.periodEnd.description
        createdAt = report.createdAt.timeIntervalSince1970
        generator = report.summary.generator.rawValue
        summaryJSON = try JSONEncoder().encode(report.summary)
    }

    func model() throws -> StoredReport {
        StoredReport(
            periodStart: try Self.day(periodStart),
            periodEnd: try Self.day(periodEnd),
            createdAt: Date(timeIntervalSince1970: createdAt),
            summary: try JSONDecoder().decode(ComposedSummary.self, from: summaryJSON)
        )
    }

    private static func day(_ text: String) throws -> Day {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { throw DatabaseError(message: "Invalid day") }
        return Day(year: parts[0], month: parts[1], day: parts[2])
    }
}
