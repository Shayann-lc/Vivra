import SwiftUI
import SyncCore

extension PermissionGroup {
    var symbol: String {
        switch self {
        case .sleep: "bed.double"
        case .heart: "heart"
        case .activity: "figure.walk"
        case .workouts: "figure.run"
        case .mind: "brain.head.profile"
        case .nutrition: "fork.knife"
        case .body: "figure.stand"
        }
    }

    var title: String {
        switch self {
        case .sleep: String(localized: "Sleep")
        case .heart: String(localized: "Heart")
        case .activity: String(localized: "Activity")
        case .workouts: String(localized: "Workouts")
        case .mind: String(localized: "State of Mind")
        case .nutrition: String(localized: "Nutrition and Hydration")
        case .body: String(localized: "Body Measurements")
        }
    }

    var explanation: String {
        switch self {
        case .sleep:
            String(
                localized:
                    "Vivra reads your sleep stages and time in bed to show how long you sleep and how it lines up with the rest of your data."
            )
        case .heart:
            String(
                localized:
                    "Vivra reads heart rate, resting heart rate, heart rate variability, walking heart rate and VO2 max to show your trends. It also lists ECG recordings and irregular rhythm notifications as Apple Health recorded them, without interpreting them."
            )
        case .activity:
            String(
                localized:
                    "Vivra reads steps, active and resting energy, exercise minutes, walking and running distance and stand hours."
            )
        case .workouts:
            String(
                localized:
                    "Vivra reads your workouts (type, duration, energy and distance) to see how they line up with your sleep and heart data. It doesn't read workout routes."
            )
        case .mind:
            String(
                localized:
                    "Vivra reads State of Mind entries and mindful minutes, alongside the mood, energy and stress you log in Vivra."
            )
        case .nutrition:
            String(
                localized:
                    "Vivra reads what apps such as MyFitnessPal or Cronometer save to Apple Health: food energy, protein, carbohydrates, fat, water, caffeine and alcoholic drinks."
            )
        case .body:
            String(
                localized:
                    "Vivra reads weight, body fat, respiratory rate, blood oxygen and sleeping wrist temperature.")
        }
    }
}

/// Asks for groups added since the person last answered (Phase 2 added
/// several), one at a time.
struct PermissionReviewView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(
                        "Vivra can now read more from Apple Health. Choose which of these to allow. You can change this later in Settings › Privacy & Security › Health › Vivra."
                    )
                    .foregroundStyle(.secondary)
                }
                ForEach(model.pendingPermissionGroups) { group in
                    Section {
                        Label(group.title, systemImage: group.symbol)
                            .font(.headline)
                        Text(group.explanation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Allow Access") { Task { await model.requestPermission(group) } }
                            .disabled(!model.isHealthAvailable)
                        Button("Not Now") { model.markRequested(group) }
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("New Health Data")
            .toolbar {
                Button("Done") { dismiss() }
            }
            .onChange(of: model.pendingPermissionGroups.isEmpty) { _, isEmpty in
                if isEmpty {
                    dismiss()
                    Task { await model.sync() }
                }
            }
        }
    }
}
