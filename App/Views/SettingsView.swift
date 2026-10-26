import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(
                        "App Lock",
                        isOn: Binding(
                            get: { model.preferences.appLockEnabled },
                            set: { enabled in Task { await model.lock.setEnabled(enabled) } }
                        )
                    )
                    .disabled(!AppLock.canAuthenticate)
                    if model.preferences.appLockEnabled {
                        Picker(
                            "Lock",
                            selection: Binding(
                                get: { model.preferences.appLockTimeout },
                                set: { model.preferences.appLockTimeout = $0 }
                            )
                        ) {
                            ForEach(AppLockTimeout.allCases) { Text($0.label).tag($0) }
                        }
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text(
                        AppLock.canAuthenticate
                            ? "Require Face ID or your passcode to open Vivra."
                            : "Set a passcode on this iPhone to use App Lock."
                    )
                }

                Section("Apple Health") {
                    Text(
                        "To change which data Vivra can read, go to Settings › Privacy & Security › Health › Vivra. "
                            + "Vivra only reads from Apple Health and never changes it."
                    )
                    .foregroundStyle(.secondary)
                }

                Section("About") {
                    NavigationLink("Not Medical Advice") {
                        ScrollView {
                            Text(Copy.disclaimer).padding()
                        }
                        .navigationTitle("Not Medical Advice")
                    }
                }

                Section {
                    Button("Delete All Vivra Data", role: .destructive) { confirmingDelete = true }
                } footer: {
                    Text(
                        "Deletes everything Vivra has stored on this iPhone, including its encryption key. "
                            + "Your Apple Health data isn't affected."
                    )
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Delete all Vivra data?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) {
                    Task { _ = await model.deleteAllData() }
                }
            } message: {
                Text("This can't be undone.")
            }
        }
    }
}
