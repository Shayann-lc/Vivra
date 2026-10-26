import Foundation

/// A 256-bit SQLCipher key.
///
/// The key is random, so it is handed to SQLCipher as a raw key
/// (`x'<hex>'`). That skips SQLCipher's passphrase KDF, which exists to
/// stretch human-chosen passwords and would only slow every connection open.
public struct DatabaseKey: Sendable, Equatable {
    public static let byteCount = 32

    public let bytes: Data

    public init(bytes: Data) throws(DatabaseKeyError) {
        guard bytes.count == Self.byteCount else {
            throw .invalidLength(bytes.count)
        }
        self.bytes = bytes
    }

    /// The value for SQLCipher's `PRAGMA key`, in raw-key form.
    var sqlCipherRawKey: String {
        "x'" + bytes.map { String(format: "%02X", $0) }.joined() + "'"
    }
}

public enum DatabaseKeyError: Error, Equatable {
    case invalidLength(Int)
    case randomGenerationFailed(Int32)
    case keychain(Int32)
    case unexpectedKeychainItem
}

/// Supplies the database key each time a connection opens, so the key is not
/// held in memory for the lifetime of the app.
public protocol DatabaseKeyProvider: Sendable {
    func databaseKey() throws -> DatabaseKey
}
