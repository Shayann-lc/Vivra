import Foundation
import SyncCore
import Testing
import VivraModel

@testable import VivraStore

@Suite struct ExportTests {
    @Test func exportsEveryTableAsJSONAndCSV() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = HealthRepository(
            database: try VivraDatabase.open(in: directory, keyProvider: StaticKeyProvider(key: makeKey(17)))
        )
        let source = SourceInfo(bundleIdentifier: "com.apple.health.watch", name: "Watch")
        let start = Date(timeIntervalSince1970: 1_775_000_000)
        try await repository.apply(
            ChangeBatch(
                quantitySamples: [
                    QuantitySample(
                        id: UUID(), kind: .restingHeartRate, start: start, end: start, value: 58, source: source)
                ],
                newAnchor: Data([1]),
                hasMore: false
            ),
            for: .restingHeartRate
        )
        try await repository.saveLog(LogEntry(kind: .note, timestamp: start, note: "lunch, \"outside\""))
        try await repository.setSetting("comparison.group", "women")

        let bundle = try await repository.exportAll(at: start)
        let files = try bundle.files()

        #expect(bundle.quantitySamples.count == 1)
        #expect(bundle.logs.count == 1)
        #expect(bundle.settings == ["comparison.group": "women"])
        #expect(files.count == 11)
        let logsCSV = String(decoding: try #require(files["logs.csv"]), as: UTF8.self)
        #expect(logsCSV.contains("\"lunch, \"\"outside\"\"\""))
        let json = try #require(
            JSONSerialization.jsonObject(with: try #require(files["vivra-export.json"])) as? [String: Any])
        #expect(json["formatVersion"] as? Int == 1)
        #expect((json["quantitySamples"] as? [Any])?.count == 1)
    }
}
