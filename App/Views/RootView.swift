import SwiftUI

struct RootView: View {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .overlay {
                if model.lock.isLocked {
                    LockView(lock: model.lock)
                } else if scenePhase != .active {
                    // Hides health data from the app switcher snapshot.
                    PrivacyCover()
                }
            }
            .task { await model.start() }
            .onOpenURL { url in
                if url == QuickLogLink.url { model.quickLogRequested = true }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    model.lock.didEnterBackground(at: .now)
                case .active:
                    model.lock.didBecomeActive(at: .now)
                    Task {
                        await model.start()
                        await model.sync()
                    }
                default:
                    break
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .starting:
            ProgressView("Opening Vivra")
        case .storeUnavailable:
            ContentUnavailableView(
                "Vivra can't open its data right now",
                systemImage: "lock",
                description: Text(
                    "Vivra's data is only readable while your iPhone is unlocked. Unlock it and try again.")
            )
            .overlay(alignment: .bottom) {
                Button("Try Again") { Task { await model.start() } }
                    .buttonStyle(.borderedProminent)
                    .padding()
            }
        case .onboarding:
            OnboardingView(model: model)
        case .ready:
            MainTabView(model: model)
        case .deleted:
            DeletedView(model: model)
        }
    }
}

struct MainTabView: View {
    enum Selection: Hashable {
        case dashboard, log, insights, settings
    }

    @Bindable var model: AppModel
    @State private var selection = Selection.dashboard

    var body: some View {
        TabView(selection: $selection) {
            Tab("Dashboard", systemImage: "square.grid.2x2", value: .dashboard) {
                DashboardView(model: model)
            }
            Tab("Log", systemImage: "plus.circle", value: .log) {
                QuickLogView(model: model)
            }
            Tab("Insights", systemImage: "text.alignleft", value: .insights) {
                InsightsView(model: model)
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView(model: model)
            }
        }
        .onChange(of: model.quickLogRequested, initial: true) { _, requested in
            if requested {
                selection = .log
                model.quickLogRequested = false
            }
        }
    }
}

struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            Label("Vivra", systemImage: "heart.text.square")
                .font(.title.bold())
                .foregroundStyle(.secondary)
        }
        .ignoresSafeArea()
    }
}

struct LockView: View {
    let lock: AppLock

    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Vivra is locked")
                    .font(.title2.bold())
                Button("Unlock") { Task { await lock.unlock() } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .ignoresSafeArea()
        .task { await lock.unlock() }
    }
}

struct DeletedView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 20) {
            ContentUnavailableView(
                "All Vivra data has been deleted",
                systemImage: "checkmark.circle",
                description: Text(
                    "Your Apple Health data hasn't been touched. To change which Health data Vivra can read, go to Settings › Privacy & Security › Health › Vivra."
                )
            )
            if let report = model.lastDeletionReport, !report.isComplete {
                Label(
                    "Some data couldn't be confirmed as deleted. Deleting Vivra from your iPhone removes everything.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Button("Start Again") { Task { await model.start() } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
