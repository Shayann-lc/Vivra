import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

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

                Section {
                    Toggle(
                        "Daily Reminder",
                        isOn: Binding(
                            get: { model.preferences.remindersEnabled },
                            set: { enabled in Task { await model.setReminders(enabled: enabled) } }
                        )
                    )
                    if model.preferences.remindersEnabled {
                        DatePicker(
                            "Time",
                            selection: Binding(
                                get: { Self.date(minutes: model.preferences.reminderMinutes) },
                                set: { date in Task { await model.setReminderTime(minutes: Self.minutes(date)) } }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text(
                        "At most one gentle reminder a day, skipped once you've checked in. "
                            + "Reminders stop on their own if you haven't opened Vivra for a week."
                    )
                }

                Section {
                    Toggle(
                        "Save Mood and Drinks to Health",
                        isOn: Binding(
                            get: { model.preferences.writeBackEnabled },
                            set: { enabled in Task { await model.setWriteBack(enabled) } }
                        )
                    )
                    .disabled(!model.isHealthAvailable)
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text(
                        "Mood is saved as State of Mind, and water, caffeine and alcohol as dietary data, so other apps "
                            + "can use them. Energy, stress, meals and notes stay in Vivra. Deleting an entry in Vivra "
                            + "also deletes it from Health."
                    )
                }

                Section {
                    Text(
                        "To change which data Vivra can read, go to Settings › Privacy & Security › Health › Vivra. "
                            + "Apart from mood and drinks, when you turn that on, Vivra only reads from Apple Health."
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
                            + "Your Apple Health data isn't affected; anything Vivra saved there stays until you "
                            + "delete it in the Health app."
                    )
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                Button("Done") { dismiss() }
            }
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

    private static func date(minutes: Int) -> Date {
        Calendar.autoupdatingCurrent.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now)
            ?? .now
    }

    private static func minutes(_ date: Date) -> Int {
        let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 19) * 60 + (components.minute ?? 0)
    }
}
