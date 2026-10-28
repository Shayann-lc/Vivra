import Foundation
import VivraLogging
import WidgetKit

/// Keeps the Daily Summary widget's file in step with today's check-in. The
/// file exists only while the widget is installed (PLAN Phase 6).
struct WidgetSummaryPublisher: Sendable {
    /// The App Group container, or nil when the entitlement is missing.
    var directory: @Sendable () -> URL?
    var isWidgetInstalled: @Sendable () async -> Bool
    var reloadWidget: @Sendable () -> Void

    static let live = WidgetSummaryPublisher(
        directory: { WidgetSummaryFile.defaultDirectory },
        isWidgetInstalled: {
            let configurations = (try? await WidgetCenter.shared.currentConfigurations()) ?? []
            return configurations.contains { $0.kind == WidgetSummaryFile.widgetKind }
        },
        reloadWidget: { WidgetCenter.shared.reloadTimelines(ofKind: WidgetSummaryFile.widgetKind) }
    )

    /// Writes `summary` if the widget is installed; otherwise, or when
    /// `summary` is nil, removes any file left behind.
    func publish(_ summary: WidgetSummary?) async {
        guard let file = directory()?.appendingPathComponent(WidgetSummaryFile.fileName) else { return }
        if let summary, await isWidgetInstalled() {
            do {
                // Widgets render while the phone is locked, so the file stays
                // readable after the first unlock; the widget redacts it on a
                // locked screen.
                try JSONEncoder().encode(summary).write(
                    to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                Log.app.failure("Widget summary write failed", code: (error as NSError).code)
            }
        } else {
            remove()
            return
        }
        reloadWidget()
    }

    func remove() {
        guard let file = directory()?.appendingPathComponent(WidgetSummaryFile.fileName),
            FileManager.default.fileExists(atPath: file.path)
        else { return }
        do {
            try FileManager.default.removeItem(at: file)
        } catch {
            Log.app.failure("Widget summary delete failed", code: (error as NSError).code)
        }
        reloadWidget()
    }
}
