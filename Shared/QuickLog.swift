import AppIntents
import Foundation

/// The deep link widgets use to open Quick Log.
enum QuickLogLink {
    static let url = URL(string: "vivra://quick-log")!
}

/// Hands "open Quick Log" requests to the app. Compiled into the widget
/// extension too, where nothing registers a handler: the intent below opens
/// the app, and the system runs `perform` in the app's process.
@MainActor
final class QuickLogRouter {
    static let shared = QuickLogRouter()

    var handler: (() -> Void)? {
        didSet {
            if pending, let handler {
                pending = false
                handler()
            }
        }
    }
    private var pending = false

    func open() {
        if let handler { handler() } else { pending = true }
    }
}

/// Opens Vivra at Quick Log. Used by the Control Center / Lock Screen control
/// and App Shortcuts. It carries no data and reads none.
struct OpenQuickLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Quick Log"
    static let description = IntentDescription("Opens Vivra at Quick Log to record mood, drinks and meals.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickLogRouter.shared.open()
        return .result()
    }
}
