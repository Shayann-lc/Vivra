import Foundation
import Testing

@testable import Vivra

@MainActor
@Suite struct AppModelTests {
    /// End to end inside the host app: real Keychain, real SQLCipher, real
    /// Data Protection attribute. Uses a fixed test-only Keychain service so
    /// repeated runs reuse one item instead of accumulating them.
    @Test func startOpensTheEncryptedStore() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppModelTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = AppModel(
            storeDirectory: { directory },
            keychainService: "app.vivra.apptests.database-key"
        )
        await model.start()

        #expect(model.storeState == .ready)
        #expect(model.database != nil)
    }
}
