import Foundation
import Testing

@testable import Vivra

/// End to end inside the host app: real Keychain, real SQLCipher. Keychain
/// access needs an app's entitlements on the simulator, so Keychain behaviour
/// is tested here rather than in VivraStore's package tests.
///
/// Every test uses the same test-only Keychain service, so repeated runs
/// reuse one item instead of accumulating them.
@MainActor
@Suite(.serialized) struct AppModelTests {
    private static let keychainService = "app.vivra.apptests.database-key"

    private static func makeModel(directory: URL) -> AppModel {
        AppModel(storeDirectory: { directory }, keychainService: keychainService)
    }

    private static func makeTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AppModelTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func startOpensTheEncryptedStore() async {
        let directory = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = Self.makeModel(directory: directory)
        await model.start()

        #expect(model.storeState == .ready)
        #expect(model.database != nil)
    }

    /// A second launch must find the key the first one stored. If the key
    /// were regenerated, SQLCipher would refuse the existing file.
    @Test func secondLaunchReusesTheStoredKey() async {
        let directory = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstLaunch = Self.makeModel(directory: directory)
        await firstLaunch.start()
        #expect(firstLaunch.storeState == .ready)

        let secondLaunch = Self.makeModel(directory: directory)
        await secondLaunch.start()
        #expect(secondLaunch.storeState == .ready)
    }
}
