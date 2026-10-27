import SwiftUI

/// Show, hide and reorder Today's cards in one place (docs/UX_RESEARCH.md §3).
struct CardEditorView: View {
    let preferences: Preferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(preferences.todayCardOrder) { card in
                        Toggle(
                            card.title,
                            isOn: Binding(
                                get: { !preferences.hiddenTodayCards.contains(card) },
                                set: { visible in
                                    if visible {
                                        preferences.hiddenTodayCards.remove(card)
                                    } else {
                                        preferences.hiddenTodayCards.insert(card)
                                    }
                                }
                            )
                        )
                    }
                    .onMove { source, destination in
                        preferences.todayCardOrder.move(fromOffsets: source, toOffset: destination)
                    }
                } footer: {
                    Text("Drag to reorder. At a glance, your progress and Quick Log always stay at the top.")
                }
                Section {
                    Button("Reset to Default") {
                        preferences.todayCardOrder = TodayCard.defaultOrder
                        preferences.hiddenTodayCards = []
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Customize Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }
}
