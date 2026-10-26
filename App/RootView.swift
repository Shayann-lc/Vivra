import SwiftUI

/// Phase 0 placeholder: confirms the encrypted store opens on launch.
struct RootView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            Text("Vivra")
                .font(.largeTitle.bold())
            switch model.storeState {
            case .opening:
                ProgressView("Preparing secure storage")
            case .ready:
                Label("Secure storage ready", systemImage: "lock.shield")
                    .foregroundStyle(.secondary)
            case .failed:
                Text("Secure storage couldn't be opened. Try restarting Vivra.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

#Preview {
    RootView(model: AppModel())
}
