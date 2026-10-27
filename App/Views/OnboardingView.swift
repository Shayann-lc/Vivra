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
                Button("Not Now") {
                    model.markRequested(group)
                    step = next(after: group)
                }

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
