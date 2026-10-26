import Foundation
import GRDB
import VivraLogging

/// The encrypted SQLite database holding all of Vivra's data.
///
/// Two layers protect it at rest:
/// - SQLCipher encrypts every page with a key from a `DatabaseKeyProvider`.
/// - The containing directory uses Data Protection `complete`, so the files
///   (including `-wal` and `-shm`, which inherit the directory's class) are
///   unreadable while the device is locked.
public final class VivraDatabase: Sendable {
    public static let fileName = "vivra.sqlite"

    public let writer: any DatabaseWriter

    private init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    /// The default location: `Application Support/Database/`.
    public static func defaultDirectory() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Database", isDirectory: true)
    }

    /// Opens (creating if needed) the database in `directory` and applies
    /// pending migrations.
    public static func open(
        in directory: URL,
        keyProvider: any DatabaseKeyProvider
    ) throws -> VivraDatabase {
        try prepareDirectory(directory)

        var config = Configuration()
        config.prepareDatabase { db in
            // Fetch the key per connection rather than capturing it, so it
            // isn't kept in memory between opens.
            try db.usePassphrase(keyProvider.databaseKey().sqlCipherRawKey)
        }

        let path = directory.appendingPathComponent(fileName).path
        let pool = try DatabasePool(path: path, configuration: config)
        try Migrations.migrator.migrate(pool)
        Log.store.event("Database opened")
        return VivraDatabase(writer: pool)
    }

    /// Identifiers of the migrations applied so far, in order.
    public func appliedMigrations() throws -> [String] {
        try writer.read { db in try Migrations.migrator.appliedMigrations(db) }
    }

    /// Closes every connection. The database can't be used afterwards.
    public func close() throws {
        if let pool = writer as? DatabasePool {
            try pool.close()
        }
    }

    /// Deletes the database files. Call `close()` on any open instance first.
    public static func destroy(in directory: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
        Log.store.event("Database deleted")
    }

    private static func prepareDirectory(_ directory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: directory.path
            )
        #endif
    }
}
