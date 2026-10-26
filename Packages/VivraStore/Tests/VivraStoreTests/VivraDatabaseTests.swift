import Foundation
import GRDB
import Testing

@testable import VivraStore

private struct StaticKeyProvider: DatabaseKeyProvider {
    let key: DatabaseKey
    func databaseKey() throws -> DatabaseKey { key }
}

private func makeKey(_ byte: UInt8) throws -> DatabaseKey {
    try DatabaseKey(bytes: Data(repeating: byte, count: DatabaseKey.byteCount))
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("VivraStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite struct VivraDatabaseTests {
    @Test func opensAndAppliesMigrations() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try VivraDatabase.open(in: directory, keyProvider: StaticKeyProvider(key: makeKey(1)))

        #expect(try database.appliedMigrations() == ["v1_settings"])
        let hasSettingTable = try database.writer.read { db in try db.tableExists("setting") }
        #expect(hasSettingTable)
    }

    @Test func fileIsNotPlaintextSQLite() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try VivraDatabase.open(in: directory, keyProvider: StaticKeyProvider(key: makeKey(2)))
        try database.writer.write { db in
            try db.execute(sql: "INSERT INTO setting (key, value) VALUES ('probe', 'needle-value')")
        }
        _ = try database.writer.writeWithoutTransaction { db in
            try db.checkpoint(.truncate)
        }

        let contents = try Data(contentsOf: directory.appendingPathComponent(VivraDatabase.fileName))
        let sqliteMagic = Data("SQLite format 3\u{0}".utf8)
        #expect(contents.prefix(sqliteMagic.count) != sqliteMagic)
        #expect(contents.range(of: Data("needle-value".utf8)) == nil)
    }

    @Test func reopensWithSameKey() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = StaticKeyProvider(key: try makeKey(3))

        do {
            let database = try VivraDatabase.open(in: directory, keyProvider: provider)
            try database.writer.write { db in
                try db.execute(sql: "INSERT INTO setting (key, value) VALUES ('k', 'v')")
            }
        }

        let reopened = try VivraDatabase.open(in: directory, keyProvider: provider)
        let value = try reopened.writer.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = 'k'")
        }
        #expect(value == "v")
    }

    @Test func refusesWrongKey() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try VivraDatabase.open(in: directory, keyProvider: StaticKeyProvider(key: makeKey(4)))

        #expect(throws: DatabaseError.self) {
            _ = try VivraDatabase.open(in: directory, keyProvider: StaticKeyProvider(key: makeKey(5)))
        }
    }

    #if os(iOS)
        @Test func directoryUsesCompleteDataProtection() throws {
            let directory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }

            _ = try VivraDatabase.open(in: directory, keyProvider: StaticKeyProvider(key: makeKey(6)))

            let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
            #expect(attributes[.protectionKey] as? FileProtectionType == .complete)
        }
    #endif
}

@Suite struct DatabaseKeyTests {
    @Test func rejectsWrongLength() {
        #expect(throws: DatabaseKeyError.invalidLength(16)) {
            _ = try DatabaseKey(bytes: Data(count: 16))
        }
    }

    @Test func formatsRawKeyLiteral() throws {
        let key = try DatabaseKey(bytes: Data((0..<32).map { UInt8($0) }))
        #expect(key.sqlCipherRawKey == "x'000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F'")
    }

    @Test func generatedKeysAreRandom() throws {
        #expect(try KeychainKeyProvider.generateKey() != KeychainKeyProvider.generateKey())
    }
}

@Suite(.serialized) struct KeychainKeyProviderTests {
    private let provider = KeychainKeyProvider(service: "app.vivra.tests.\(UUID().uuidString)")

    @Test func createsKeyOnceAndReturnsItAfterwards() throws {
        defer { try? provider.deleteKey() }

        let first = try provider.databaseKey()
        let second = try provider.databaseKey()

        #expect(first == second)
    }

    @Test func deleteKeyForcesANewKey() throws {
        defer { try? provider.deleteKey() }

        let first = try provider.databaseKey()
        try provider.deleteKey()
        let second = try provider.databaseKey()

        #expect(first != second)
    }

    @Test func deletingAMissingKeySucceeds() throws {
        try provider.deleteKey()
    }
}
