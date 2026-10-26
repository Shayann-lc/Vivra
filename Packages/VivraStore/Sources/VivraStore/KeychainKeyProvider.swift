import Foundation
import Security
import VivraLogging

/// Stores the database key in the Keychain.
///
/// The item is `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: readable only
/// while the device is unlocked, never synced to iCloud Keychain and never
/// restored to another device from a backup. Losing it (new device, restore
/// from backup) means the local store can't be opened and is recreated; Apple
/// Health remains the source of truth for synced data.
public struct KeychainKeyProvider: DatabaseKeyProvider {
    public static let defaultService = "app.vivra.database-key"

    private let service: String
    private let account = "primary"

    public init(service: String = KeychainKeyProvider.defaultService) {
        self.service = service
    }

    /// Returns the stored key, creating and storing a new one on first use.
    public func databaseKey() throws -> DatabaseKey {
        if let existing = try readKey() {
            return existing
        }
        let key = try Self.generateKey()
        let status = SecItemAdd(
            baseQuery.merging([
                kSecValueData as String: key.bytes,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ]) { $1 } as CFDictionary,
            nil
        )
        switch status {
        case errSecSuccess:
            Log.store.event("Created database key")
            return key
        case errSecDuplicateItem:
            // Another connection created it first; use theirs.
            guard let existing = try readKey() else { throw DatabaseKeyError.unexpectedKeychainItem }
            return existing
        default:
            Log.store.failure("Keychain add failed", code: Int(status))
            throw DatabaseKeyError.keychain(status)
        }
    }

    /// Removes the key. The database becomes permanently unreadable.
    public func deleteKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            Log.store.failure("Keychain delete failed", code: Int(status))
            throw DatabaseKeyError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    private func readKey() throws -> DatabaseKey? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            baseQuery.merging([
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]) { $1 } as CFDictionary,
            &result
        )
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw DatabaseKeyError.unexpectedKeychainItem }
            return try DatabaseKey(bytes: data)
        case errSecItemNotFound:
            return nil
        default:
            Log.store.failure("Keychain read failed", code: Int(status))
            throw DatabaseKeyError.keychain(status)
        }
    }

    static func generateKey() throws -> DatabaseKey {
        var bytes = Data(count: DatabaseKey.byteCount)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, DatabaseKey.byteCount, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw DatabaseKeyError.randomGenerationFailed(status) }
        return try DatabaseKey(bytes: bytes)
    }
}
