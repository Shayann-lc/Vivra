import SwiftUI
import UIKit

@main
struct VivraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView(model: delegate.model)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    let model = AppModel.forLaunch()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // HealthKit observers must be registered at launch so background
        // deliveries reach the app.
        if model.preferences.onboardingCompleted {
            model.startObservingHealth()
        }
        let model = model
        QuickLogRouter.shared.handler = { model.quickLogRequested = true }
        Task { await model.start() }
        return true
    }
}
