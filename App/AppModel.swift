import Foundation
import Observation
import VivraLogging
import VivraStore

@MainActor
@Observable
final class AppModel {
    enum StoreState: Equatable {
        case opening
        case ready
        case failed
    }

    private(set) var storeState: StoreState = .opening
    private(set) var database: VivraDatabase?

    private let storeDirectory: @Sendable () throws -> URL
    private let keyProvider: any DatabaseKeyProvider

    init(
        storeDirectory: @escaping @Sendable () throws -> URL = { try VivraDatabase.defaultDirectory() },
        keychainService: String = KeychainKeyProvider.defaultService
    ) {
        self.storeDirectory = storeDirectory
        self.keyProvider = KeychainKeyProvider(service: keychainService)
    }

    /// Opens the encrypted store off the main actor. Safe to call repeatedly.
    func start() async {
        guard database == nil else { return }
        storeState = .opening
        let storeDirectory = storeDirectory
        let keyProvider = keyProvider
        do {
            database = try await Task.detached(priority: .userInitiated) {
                try VivraDatabase.open(in: storeDirectory(), keyProvider: keyProvider)
            }.value
            storeState = .ready
        } catch {
            Log.app.failure("Store open failed", code: (error as NSError).code)
            storeState = .failed
        }
    }
}
