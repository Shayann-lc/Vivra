import BackgroundTasks
import SwiftUI
import UIKit
import VivraLogging

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
        DailyCheckInTask.register(model: model)
        DailyCheckInTask.schedule()
        Task { await model.start() }
        return true
    }
}

/// Once a day, tries to make the check-in in the background so the Daily
/// Summary widget is current before the app is opened (PLAN Phase 6). iOS
/// decides when it runs; if the phone is locked, the store can't open and
/// the run does nothing.
enum DailyCheckInTask {
    static let identifier = "app.vivra.dailycheckin"

    @MainActor
    static func register(model: AppModel) {
        _ = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            let box = TaskBox(task)
            MainActor.assumeIsolated {
                let work = Task { @MainActor in await model.runBackgroundCheckIn() }
                box.task.expirationHandler = { work.cancel() }
                Task { @MainActor in
                    await work.value
                    box.task.setTaskCompleted(success: !work.isCancelled)
                    schedule()
                }
            }
        }
    }

    /// Asks for the next run in about six hours.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Log.app.failure("Daily check-in task not scheduled", code: (error as NSError).code)
        }
    }
}

/// `BGTask` isn't `Sendable`, but the scheduler calls the handler on the
/// main queue (`using: .main`) and the task is only touched there.
private struct TaskBox: @unchecked Sendable {
    let task: BGTask
    init(_ task: BGTask) { self.task = task }
}
