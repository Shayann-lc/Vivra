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
            for event in batch.categoryEvents {
                try CategoryEventRecord(event).insert(db, onConflict: .replace)
            }
            for state in batch.statesOfMind {
                try StateOfMindRecord(state).insert(db, onConflict: .replace)
            }
            for record in batch.ecgRecords {
                try ECGRecordRow(record).insert(db, onConflict: .replace)
            }
            if !batch.deletedIDs.isEmpty {
                let table = Self.table(for: type)
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

    static func table(for type: HealthDataType) -> String {
        switch type {
        case .sleep: SleepIntervalRecord.databaseTableName
        case .workouts: WorkoutRecord.databaseTableName
        case .stateOfMind: StateOfMindRecord.databaseTableName
        case .electrocardiogram: ECGRecordRow.databaseTableName
        case .standHour, .mindfulSession, .irregularRhythm: CategoryEventRecord.databaseTableName
        default: QuantitySampleRecord.databaseTableName
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

    /// Category events of `kinds` starting in `[from, to)`, oldest first.
    public func categoryEvents(_ kinds: [CategoryKind], from: Date, to: Date) async throws -> [CategoryEvent] {
        try await writer.read { db in
            try CategoryEventRecord
                .filter(kinds.map(\.rawValue).contains(Column("kind")))
                .filter(Column("start") >= from.timeIntervalSince1970 && Column("start") < to.timeIntervalSince1970)
                .order(Column("start"))
                .fetchAll(db)
                .compactMap(\.model)
        }
    }

    public func statesOfMind(from: Date, to: Date) async throws -> [StateOfMindSample] {
        try await writer.read { db in
            try StateOfMindRecord
                .filter(Column("date") >= from.timeIntervalSince1970 && Column("date") < to.timeIntervalSince1970)
                .order(Column("date"))
                .fetchAll(db)
                .compactMap(\.model)
        }
    }

    /// ECG recordings, newest first.
    public func ecgRecords(from: Date, to: Date) async throws -> [ECGRecord] {
        try await writer.read { db in
            try ECGRecordRow
                .filter(Column("date") >= from.timeIntervalSince1970 && Column("date") < to.timeIntervalSince1970)
                .order(Column("date").desc)
                .fetchAll(db)
                .compactMap(\.model)
        }
    }

    /// Per-day, per-source totals of cumulative `kinds`. Day boundaries come
    /// from `calendar`, so days follow the person's time zone (and daylight
    /// saving) exactly; SQL only sums within them.
    public func dailySourceTotals(_ kinds: [QuantityKind], days: [Day], calendar: DayCalendar) async throws
        -> DailySourceTotals
    {
        guard !kinds.isEmpty, !days.isEmpty else { return [:] }
        var arguments: [(any DatabaseValueConvertible)?] = []
        for day in days {
            arguments += [
                day.description, calendar.start(of: day).timeIntervalSince1970,
                calendar.start(of: calendar.adding(days: 1, to: day)).timeIntervalSince1970,
            ]
        }
        arguments += kinds.map { $0.rawValue as (any DatabaseValueConvertible)? }
        let dayRows = Array(repeating: "(?, ?, ?)", count: days.count).joined(separator: ", ")
        let kindMarks = Array(repeating: "?", count: kinds.count).joined(separator: ", ")
        let sql = """
            WITH days(day, day_start, day_end) AS (VALUES \(dayRows))
            SELECT days.day AS day, q.kind AS kind, q.source_bundle_id AS source, SUM(q.value) AS total
            FROM quantity_sample q
            JOIN days ON q.start >= days.day_start AND q.start < days.day_end
            WHERE q.kind IN (\(kindMarks))
            GROUP BY days.day, q.kind, q.source_bundle_id
            """
        let dayLookup = Dictionary(uniqueKeysWithValues: days.map { ($0.description, $0) })
        let statementArguments = StatementArguments(arguments)
        return try await writer.read { db in
            var totals: DailySourceTotals = [:]
            for row in try Row.fetchAll(db, sql: sql, arguments: statementArguments) {
                guard let day = dayLookup[row["day"]], let kind = QuantityKind(rawValue: row["kind"]) else { continue }
                totals[kind, default: [:]][day, default: [:]][row["source"]] = row["total"]
            }
            return totals
        }
    }

    /// Everything the insight engine needs for the complete days in
    /// `[first, last]`. Sleep starts the evening before `first`.
    public func dataset(first: Day, last: Day, calendar: DayCalendar) async throws -> HealthDataset {
        let from = calendar.start(of: first)
        let to = calendar.start(of: calendar.adding(days: 1, to: last))
        var days: [Day] = []
        var day = first
        while day <= last {
            days.append(day)
            day = calendar.adding(days: 1, to: day)
        }
        async let sleep = sleepIntervals(endingFrom: calendar.adding(hours: -6, to: from), to: to)
        async let samples = quantitySamples(HealthDataset.averageKinds, from: from, to: to)
        async let totals = dailySourceTotals(HealthDataset.cumulativeKinds, days: days, calendar: calendar)
        async let workouts = workouts(from: from, to: to)
        async let events = categoryEvents([.standHour, .mindfulSession], from: from, to: to)
        async let states = statesOfMind(from: from, to: to)
        async let logs = logs(from: from, to: to)
        return try await HealthDataset(
            sleepIntervals: sleep,
            samples: samples,
            dailySourceTotals: totals,
            workouts: workouts,
            categoryEvents: events,
            statesOfMind: states,
            logs: logs
        )
    }

    // MARK: Logs

    public func saveLog(_ entry: LogEntry) async throws {
        let record = LogEntryRecord(entry)
        try await writer.write { db in try record.insert(db, onConflict: .replace) }
    }

    public func deleteLog(id: UUID) async throws {
        _ = try await writer.write { db in try LogEntryRecord.deleteOne(db, key: id.uuidString) }
    }

    /// Log entries in `[from, to)`, newest first.
    public func logs(from: Date, to: Date) async throws -> [LogEntry] {
        try await writer.read { db in
            try LogEntryRecord
                .filter(
                    Column("timestamp") >= from.timeIntervalSince1970 && Column("timestamp") < to.timeIntervalSince1970
                )
                .order(Column("timestamp").desc)
                .fetchAll(db)
                .compactMap(\.model)
        }
    }

    // MARK: Reports

    public func saveReport(_ report: StoredReport) async throws {
        let record = try ReportRecord(report)
        try await writer.write { db in try record.insert(db) }
    }

    public func latestReport(kind: ReportKind) async throws -> StoredReport? {
        try await writer.read { db in
            try ReportRecord.filter(Column("kind") == kind.rawValue).order(Column("id").desc).fetchOne(db)
        }
        .flatMap { try? $0.model() }
    }
}

/// A generated summary or check-in, as saved.
public struct StoredReport: Sendable, Equatable {
    public let kind: ReportKind
    public let periodStart: Day
    public let periodEnd: Day
    public let createdAt: Date
    public let summary: ComposedSummary

    public init(kind: ReportKind, periodStart: Day, periodEnd: Day, createdAt: Date, summary: ComposedSummary) {
        self.kind = kind
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
    var kind: String

    enum CodingKeys: String, CodingKey {
        case id, generator, kind
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
        kind = report.kind.rawValue
    }

    func model() throws -> StoredReport {
        StoredReport(
            kind: ReportKind(rawValue: kind) ?? .weekly,
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

private struct CategoryEventRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "category_event"

    var id: String
    var kind: String
    var start: Double
    var end: Double
    var value: Int
    var sourceBundleID: String
    var sourceName: String

    enum CodingKeys: String, CodingKey {
        case id, kind, start, end, value
        case sourceBundleID = "source_bundle_id"
        case sourceName = "source_name"
    }

    init(_ event: CategoryEvent) {
        id = event.id.uuidString
        kind = event.kind.rawValue
        start = event.start.timeIntervalSince1970
        end = event.end.timeIntervalSince1970
        value = event.value
        sourceBundleID = event.source.bundleIdentifier
        sourceName = event.source.name
    }

    var model: CategoryEvent? {
        guard let uuid = UUID(uuidString: id), let kind = CategoryKind(rawValue: kind) else { return nil }
        return CategoryEvent(
            id: uuid,
            kind: kind,
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: end),
            value: value,
            source: SourceInfo(bundleIdentifier: sourceBundleID, name: sourceName)
        )
    }
}

private struct StateOfMindRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "state_of_mind"

    var id: String
    var date: Double
    var kind: String
    var valence: Double
    var labels: String
    var associations: String
    var sourceBundleID: String
    var sourceName: String

    enum CodingKeys: String, CodingKey {
        case id, date, kind, valence, labels, associations
        case sourceBundleID = "source_bundle_id"
        case sourceName = "source_name"
    }

    init(_ state: StateOfMindSample) {
        id = state.id.uuidString
        date = state.date.timeIntervalSince1970
        kind = state.kind.rawValue
        valence = state.valence
        labels = state.labels.map(String.init).joined(separator: ",")
        associations = state.associations.map(String.init).joined(separator: ",")
        sourceBundleID = state.source.bundleIdentifier
        sourceName = state.source.name
    }

    var model: StateOfMindSample? {
        guard let uuid = UUID(uuidString: id), let kind = StateOfMindSample.Kind(rawValue: kind) else { return nil }
        return StateOfMindSample(
            id: uuid,
            date: Date(timeIntervalSince1970: date),
            kind: kind,
            valence: valence,
            labels: labels.split(separator: ",").compactMap { Int($0) },
            associations: associations.split(separator: ",").compactMap { Int($0) },
            source: SourceInfo(bundleIdentifier: sourceBundleID, name: sourceName)
        )
    }
}

private struct ECGRecordRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "ecg_record"

    var id: String
    var date: Double
    var classification: String
    var sourceBundleID: String
    var sourceName: String

    enum CodingKeys: String, CodingKey {
        case id, date, classification
        case sourceBundleID = "source_bundle_id"
        case sourceName = "source_name"
    }

    init(_ record: ECGRecord) {
        id = record.id.uuidString
        date = record.date.timeIntervalSince1970
        classification = record.classification.rawValue
        sourceBundleID = record.source.bundleIdentifier
        sourceName = record.source.name
    }

    var model: ECGRecord? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return ECGRecord(
            id: uuid,
            date: Date(timeIntervalSince1970: date),
            classification: ECGRecord.Classification(rawValue: classification) ?? .unrecognized,
            source: SourceInfo(bundleIdentifier: sourceBundleID, name: sourceName)
        )
    }
}

private struct LogEntryRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "log_entry"

    var id: String
    var kind: String
    var timestamp: Double
    var scale: Int?
    var drink: String?
    var amount: Double?
    var note: String?
    var healthKitSampleID: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, timestamp, scale, drink, amount, note
        case healthKitSampleID = "healthkit_sample_id"
    }

    init(_ entry: LogEntry) {
        id = entry.id.uuidString
        kind = entry.kind.rawValue
        timestamp = entry.timestamp.timeIntervalSince1970
        scale = entry.scale
        drink = entry.drink?.rawValue
        amount = entry.amount
        note = entry.note
        healthKitSampleID = entry.healthKitSampleID?.uuidString
    }

    var model: LogEntry? {
        guard let uuid = UUID(uuidString: id), let kind = LogEntry.Kind(rawValue: kind) else { return nil }
        return LogEntry(
            id: uuid,
            kind: kind,
            timestamp: Date(timeIntervalSince1970: timestamp),
            scale: scale,
            drink: drink.flatMap(Drink.init(rawValue:)),
            amount: amount,
            note: note,
            healthKitSampleID: healthKitSampleID.flatMap(UUID.init(uuidString:))
        )
    }
}
