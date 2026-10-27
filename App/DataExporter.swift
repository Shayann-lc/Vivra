import Foundation
import VivraLogging

/// An export written to disk: a folder of files plus a zip of it, both inside
/// one temporary directory that `DataExporter.cleanUp` removes.
struct PreparedExport: Identifiable, Sendable {
    let id = UUID()
    /// Holds the folder and the zip. Removing it removes everything.
    let directory: URL
    let folder: URL
    let archive: URL
}

/// Writes export files with Data Protection `complete` and zips them with
/// `NSFileCoordinator`, so no zip library is needed (PLAN Phase 5).
enum DataExporter {
    static let directoryPrefix = "VivraExport-"

    static func write(_ files: [String: Data], name: String, in parent: URL) throws -> PreparedExport {
        let fileManager = FileManager.default
        let protection: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
        let directory = parent.appendingPathComponent(directoryPrefix + UUID().uuidString, isDirectory: true)
        let folder = directory.appendingPathComponent(name, isDirectory: true)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: protection)
            try fileManager.setAttributes(protection, ofItemAtPath: directory.path)
            for (fileName, data) in files {
                try data.write(
                    to: folder.appendingPathComponent(fileName), options: [.atomic, .completeFileProtection])
            }

            // The coordinator zips into its own temporary file, which it
            // deletes when the accessor returns, so copy it out first.
            let archive = directory.appendingPathComponent(name + ".zip")
            var coordinationError: NSError?
            var copyError: (any Error)?
            NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) {
                zipped in
                do {
                    try fileManager.copyItem(at: zipped, to: archive)
                    try fileManager.setAttributes(protection, ofItemAtPath: archive.path)
                } catch {
                    copyError = error
                }
            }
            if let error = coordinationError ?? copyError { throw error }
            return PreparedExport(directory: directory, folder: folder, archive: archive)
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    static func cleanUp(_ export: PreparedExport) {
        do { try FileManager.default.removeItem(at: export.directory) } catch {
            Log.app.failure("Export cleanup failed", code: (error as NSError).code)
        }
    }

    /// Removes exports left behind if the app was closed while sharing.
    static func removeLeftovers(in parent: URL) {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) else {
            return
        }
        for url in contents where url.lastPathComponent.hasPrefix(directoryPrefix) {
            try? fileManager.removeItem(at: url)
        }
    }
}
