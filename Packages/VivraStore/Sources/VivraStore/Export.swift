import Foundation
import GRDB
import Gamification
import InsightEngine
import NarrativeCore
import VivraModel

/// Everything Vivra stores, for the person's own export.
public struct ExportBundle: Codable, Sendable {
    public struct Report: Codable, Sendable {
        public let kind: String
        public let periodStart: String
        public let periodEnd: String
        public let createdAt: Date
        public let generator: String
        public let headline: String
        public let sentences: [String]
    }

    public struct Goal: Codable, Sendable {
        public let effectiveDay: String
        public let target: Int
    }

    public static let formatVersion = 1

    public let formatVersion: Int
    public let exportedAt: Date
    public let quantitySamples: [QuantitySample]
    public let sleepIntervals: [SleepInterval]
    public let workouts: [Workout]
    public let categoryEvents: [CategoryEvent]
    public let statesOfMind: [StateOfMindSample]
    public let ecgRecords: [ECGRecord]
    public let logs: [LogEntry]
    public let reports: [Report]
    public let goals: [Goal]
    public let events: [AppEvent]
    public let settings: [String: String]

    /// The JSON document plus one CSV per table, keyed by file name.
    public func files() throws -> [String: Data] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        func iso(_ date: Date) -> String { date.formatted(.iso8601) }
        func number(_ value: Double?) -> String { value.map { String($0) } ?? "" }
        func csv(_ header: [String], _ rows: [[String]]) -> Data {
            Data(CSVWriter.render(header: header, rows: rows).utf8)
        }

        return [
            "vivra-export.json": try encoder.encode(self),
            "quantity-samples.csv": csv(
                ["id", "kind", "start", "end", "value", "unit", "source_bundle_id", "source_name"],
                quantitySamples.map {
                    [
                        $0.id.uuidString, $0.kind.rawValue, iso($0.start), iso($0.end), String($0.value),
                        $0.kind.unit.rawValue,
                        $0.source.bundleIdentifier, $0.source.name,
                    ]
                }
            ),
            "sleep.csv": csv(
                ["id", "stage", "start", "end", "source_bundle_id", "source_name"],
                sleepIntervals.map {
                    [
                        $0.id.uuidString, $0.stage.rawValue, iso($0.start), iso($0.end), $0.source.bundleIdentifier,
                        $0.source.name,
                    ]
                }
            ),
            "workouts.csv": csv(
                [
                    "id", "activity_type", "start", "end", "duration_s", "active_energy_kcal", "distance_m",
                    "source_bundle_id",
                    "source_name",
                ],
                workouts.map {
                    [
                        $0.id.uuidString, String($0.activityType), iso($0.start), iso($0.end), String($0.duration),
                        number($0.activeEnergyKilocalories), number($0.distanceMeters), $0.source.bundleIdentifier,
                        $0.source.name,
                    ]
                }
            ),
            "category-events.csv": csv(
                ["id", "kind", "start", "end", "value", "source_bundle_id", "source_name"],
                categoryEvents.map {
                    [
                        $0.id.uuidString, $0.kind.rawValue, iso($0.start), iso($0.end), String($0.value),
                        $0.source.bundleIdentifier, $0.source.name,
                    ]
                }
            ),
            "state-of-mind.csv": csv(
                ["id", "date", "kind", "valence", "labels", "associations", "source_bundle_id", "source_name"],
                statesOfMind.map {
                    [
                        $0.id.uuidString, iso($0.date), $0.kind.rawValue, String($0.valence),
                        $0.labels.map(String.init).joined(separator: " "),
                        $0.associations.map(String.init).joined(separator: " "),
                        $0.source.bundleIdentifier, $0.source.name,
                    ]
                }
            ),
            "ecg-records.csv": csv(
                ["id", "date", "classification", "source_bundle_id", "source_name"],
                ecgRecords.map {
                    [
                        $0.id.uuidString, iso($0.date), $0.classification.rawValue, $0.source.bundleIdentifier,
                        $0.source.name,
                    ]
                }
            ),
            "logs.csv": csv(
                ["id", "kind", "timestamp", "scale", "drink", "amount", "note", "healthkit_sample_id"],
                logs.map {
                    [
                        $0.id.uuidString, $0.kind.rawValue, iso($0.timestamp), $0.scale.map(String.init) ?? "",
                        $0.drink?.rawValue ?? "", number($0.amount), $0.note ?? "",
                        $0.healthKitSampleID?.uuidString ?? "",
                    ]
                }
            ),
            "reports.csv": csv(
                ["kind", "period_start", "period_end", "created_at", "generator", "headline", "text"],
                reports.map {
                    [
                        $0.kind, $0.periodStart, $0.periodEnd, iso($0.createdAt), $0.generator, $0.headline,
                        $0.sentences.joined(separator: "\n"),
                    ]
                }
            ),
            "goals.csv": csv(["effective_day", "target"], goals.map { [$0.effectiveDay, String($0.target)] }),
            "events.csv": csv(["kind", "date"], events.map { [$0.kind.rawValue, iso($0.date)] }),
        ]
    }
}

extension HealthRepository {
    /// Reads every table. For exports only: it loads everything into memory.
    public func exportAll(at date: Date) async throws -> ExportBundle {
        let distantPast = Date(timeIntervalSince1970: 0)
        let distantFuture = Date(timeIntervalSinceNow: 10 * 365 * 86_400)
        async let samples = quantitySamples(QuantityKind.allCases, from: distantPast, to: distantFuture)
        async let sleep = sleepIntervals(endingFrom: distantPast, to: distantFuture)
        async let workouts = workouts(from: distantPast, to: distantFuture)
        async let events = categoryEvents(CategoryKind.allCases, from: distantPast, to: distantFuture)
        async let states = statesOfMind(from: distantPast, to: distantFuture)
        async let ecgs = ecgRecords(from: distantPast, to: distantFuture)
        async let logs = allLogs()
        async let reports = allReports()
        async let goals = goalChanges()
        async let appEvents = self.events()
        async let settings = allSettings()
        return try await ExportBundle(
            formatVersion: ExportBundle.formatVersion,
            exportedAt: date,
            quantitySamples: samples,
            sleepIntervals: sleep,
            workouts: workouts,
            categoryEvents: events,
            statesOfMind: states,
            ecgRecords: ecgs,
            logs: logs,
            reports: reports.map {
                ExportBundle.Report(
                    kind: $0.kind.rawValue,
                    periodStart: $0.periodStart.description,
                    periodEnd: $0.periodEnd.description,
                    createdAt: $0.createdAt,
                    generator: $0.summary.generator.rawValue,
                    headline: $0.summary.draft.headline,
                    sentences: $0.summary.draft.bullets.map(\.text)
                )
            },
            goals: goals.map { ExportBundle.Goal(effectiveDay: $0.effective.description, target: $0.target) },
            events: appEvents,
            settings: settings
        )
    }
}
