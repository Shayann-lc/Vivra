import SwiftUI
import VivraModel

/// One screen, a few taps: pick what applies and Save.
struct QuickLogView: View {
    let model: AppModel
    @State private var draft = QuickLogDraft()
    @State private var savedConfirmation = false
    @FocusState private var noteFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("How are you feeling?") {
                    ScaleChips(
                        title: "Mood", lowLabel: "Very unpleasant", highLabel: "Very pleasant", value: $draft.mood)
                    ScaleChips(title: "Energy", lowLabel: "Very low", highLabel: "Very high", value: $draft.energy)
                    ScaleChips(title: "Stress", lowLabel: "Very low", highLabel: "Very high", value: $draft.stress)
                }

                Section {
                    ForEach(Drink.allCases, id: \.self) { drink in
                        Stepper(value: binding(for: drink), in: 0...20) {
                            HStack {
                                Label(drink.title, systemImage: drink.symbol)
                                Spacer()
                                Text(drink.servingsText(draft.drinks[drink] ?? 0))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    Toggle(isOn: $draft.meal) { Label("Had a meal", systemImage: "fork.knife") }
                } header: {
                    Text("Drinks and meals")
                } footer: {
                    Text(Copy.drinkEstimates)
                }

                Section("Note") {
                    TextField("Anything else? (optional)", text: $draft.note, axis: .vertical)
                        .focused($noteFocused)
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        Text("Save").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.isEmpty)
                } footer: {
                    if model.preferences.writeBackEnabled {
                        Text("Mood and drinks are also saved to Apple Health.")
                    }
                }

                if !model.todayLogs.isEmpty {
                    Section("Logged today") {
                        ForEach(model.todayLogs) { entry in
                            LogRow(entry: entry)
                        }
                        .onDelete { offsets in
                            let entries = offsets.map { model.todayLogs[$0] }
                            Task { for entry in entries { await model.deleteLog(entry) } }
                        }
                    }
                }
            }
            .navigationTitle("Quick Log")
            .sensoryFeedback(.success, trigger: savedConfirmation)
            .task { await model.refreshTodayLogs() }
        }
    }

    private func binding(for drink: Drink) -> Binding<Int> {
        Binding(get: { draft.drinks[drink] ?? 0 }, set: { draft.drinks[drink] = $0 })
    }

    private func save() async {
        noteFocused = false
        if await model.saveQuickLog(draft) {
            draft = QuickLogDraft()
            savedConfirmation.toggle()
        }
    }
}

/// Five tappable chips; tapping the selected one clears it.
private struct ScaleChips: View {
    let title: String
    let lowLabel: String
    let highLabel: String
    @Binding var value: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.bold())
            HStack(spacing: 8) {
                ForEach(Array(LogEntry.scaleRange), id: \.self) { level in
                    Button {
                        value = value == level ? nil : level
                    } label: {
                        Text("\(level)")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                    .tint(value == level ? .accentColor : .secondary)
                    .accessibilityLabel("\(title) \(level) of 5")
                    .accessibilityAddTraits(value == level ? .isSelected : [])
                }
            }
            HStack {
                Text(lowLabel)
                Spacer()
                Text(highLabel)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack {
            Text(description)
            Spacer()
            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                .foregroundStyle(.secondary)
        }
    }

    private var description: String {
        switch entry.kind {
        case .mood: "Mood \(entry.scale ?? 0) of 5"
        case .energy: "Energy \(entry.scale ?? 0) of 5"
        case .stress: "Stress \(entry.scale ?? 0) of 5"
        case .meal: "Meal"
        case .note: entry.note ?? "Note"
        case .drink:
            if let drink = entry.drink, let amount = entry.amount {
                drink.servingsText(Int((amount / drink.amountPerServing).rounded()))
            } else {
                "Drink"
            }
        }
    }
}

extension Drink {
    var title: String {
        switch self {
        case .water: "Water"
        case .coffee: "Coffee"
        case .tea: "Tea"
        case .alcohol: "Alcohol"
        }
    }

    var symbol: String {
        switch self {
        case .water: "drop"
        case .coffee: "cup.and.saucer"
        case .tea: "mug"
        case .alcohol: "wineglass"
        }
    }

    func servingsText(_ servings: Int) -> String {
        switch self {
        case .water: servings == 1 ? "1 glass of water" : "\(servings) glasses of water"
        case .coffee: servings == 1 ? "1 cup of coffee" : "\(servings) cups of coffee"
        case .tea: servings == 1 ? "1 cup of tea" : "\(servings) cups of tea"
        case .alcohol: servings == 1 ? "1 drink" : "\(servings) drinks"
        }
    }
}
