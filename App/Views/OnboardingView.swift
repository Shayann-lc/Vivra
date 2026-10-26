import SwiftUI
import SyncCore

struct OnboardingView: View {
    let model: AppModel
    @State private var step = Step.welcome

    enum Step: Hashable {
        case welcome
        case disclaimer
        case permission(PermissionGroup)
        case finish
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            switch step {
            case .welcome:
                page(
                    symbol: "heart.text.square",
                    title: "Welcome to Vivra",
                    text: "Vivra helps you notice patterns across your sleep, heart and workouts. "
                        + "Everything is stored and analysed on this iPhone, and nothing is sent anywhere."
                )
                Spacer()
                Button("Continue") { step = .disclaimer }
                    .buttonStyle(.borderedProminent)

            case .disclaimer:
                page(symbol: "info.circle", title: "Before you start", text: Copy.disclaimer)
                Spacer()
                Button("I Understand") {
                    model.acceptDisclaimer()
                    step = .permission(.sleep)
                }
                .buttonStyle(.borderedProminent)

            case .permission(let group):
                page(symbol: group.symbol, title: group.title, text: group.explanation)
                Spacer()
                if model.isHealthAvailable {
                    Button("Allow Access") {
                        Task {
                            await model.requestPermission(group)
                            step = next(after: group)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("Apple Health isn't available on this device.")
                        .foregroundStyle(.secondary)
                }
                Button("Not Now") { step = next(after: group) }

            case .finish:
                page(
                    symbol: "checkmark.circle",
                    title: "You're all set",
                    text: "Vivra will now read the last 90 days from Apple Health. "
                        + "You can change what it reads at any time in Settings › Privacy & Security › Health › Vivra."
                )
                Spacer()
                Button("Go to Dashboard") { Task { await model.completeOnboarding() } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .animation(.default, value: step)
    }

    private func next(after group: PermissionGroup) -> Step {
        let groups = PermissionGroup.allCases
        guard let index = groups.firstIndex(of: group), index + 1 < groups.count else { return .finish }
        return .permission(groups[index + 1])
    }

    private func page(symbol: String, title: String, text: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
}

extension PermissionGroup {
    fileprivate var symbol: String {
        switch self {
        case .sleep: "bed.double"
        case .heart: "heart"
        case .workouts: "figure.run"
        }
    }

    fileprivate var title: String {
        switch self {
        case .sleep: "Sleep"
        case .heart: "Heart"
        case .workouts: "Workouts"
        }
    }

    fileprivate var explanation: String {
        switch self {
        case .sleep:
            "Vivra reads your sleep stages and time in bed to show how long you sleep and how it lines up with the rest of your data."
        case .heart:
            "Vivra reads heart rate, resting heart rate, heart rate variability, walking heart rate and VO2 max to show your trends."
        case .workouts:
            "Vivra reads your workouts (type, duration, energy and distance) to see how they line up with your sleep and heart data."
        }
    }
}
