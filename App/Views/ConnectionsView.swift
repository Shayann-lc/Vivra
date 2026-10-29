import InsightEngine
import NarrativeCore
import SwiftUI
import VivraModel

/// Opens a connection's detail, from Insights or Today.
struct ConnectionRoute: Hashable {
    let id: String
}

/// `Connections | Summaries` at the top of both halves of Insights.
struct InsightsSectionPicker: View {
    @Binding var selection: InsightsSection

    var body: some View {
        ChoiceControl(
            title: String(localized: "Insights"),
            options: [
                .init(value: InsightsSection.connections, label: String(localized: "Connections")),
                .init(value: .summaries, label: String(localized: "Summaries")),
            ],
            selection: $selection
        )
    }
}

/// A segmented control, or at the largest text sizes (where segments don't
/// grow) one button row per option with a checkmark, which wraps like any
/// other row.
struct ChoiceControl<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: String
        var id: Value { value }
    }

    let title: String
    let options: [Option]
    @Binding var selection: Value
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            ForEach(options) { option in
                Button {
                    selection = option.value
                } label: {
                    HStack {
                        Text(option.label)
                        Spacer()
                        if selection == option.value {
                            Image(systemName: "checkmark")
                                .accessibilityHidden(true)
                        }
                    }
                }
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        } else {
            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

/// Habits next to outcomes, in real units (PLAN Phase 7). Every row is a
/// template; no model is involved.
struct ConnectionsView: View {
    @Bindable var model: AppModel
    @State private var pivot = Pivot.byOutcome
    @State private var showingExplainer = false

    enum Pivot: Hashable {
        case byOutcome
        case byHabit
    }

    var body: some View {
        List {
            Section {
                InsightsSectionPicker(selection: $model.insightsSection)
            }
            if let board = model.connections {
                // In a section of its own, like the Insights picker: at the
                // largest text sizes its rows then lay out like any other.
                Section {
                    pivotPicker
                }
                Section {
                    Text(ConnectionLabels.summary(board))
                        .font(.subheadline)
                    Button {
                        showingExplainer = true
                    } label: {
                        IconText(symbol: "info.circle", text: String(localized: "How Connections works"))
                    }
                } footer: {
                    if let note = note(board) { Text(note) }
                }
                switch pivot {
                case .byOutcome: byOutcome(board)
                case .byHabit: byHabit(board)
                }
            } else {
                ProgressView()
            }
            Section {
                NavigationLink("See All Patterns as Text") { PatternsView(model: model) }
            } footer: {
                Text("\(ConnectionLabels.footer) \(Copy.shortDisclaimer)")
            }
        }
        .refreshable { await model.refreshAnalysis() }
        .sheet(isPresented: $showingExplainer) { ConnectionsExplainer() }
        .task { await model.noteViewedPatterns() }
    }

    private var pivotPicker: some View {
        ChoiceControl(
            title: String(localized: "Show"),
            options: [
                .init(value: Pivot.byOutcome, label: String(localized: "By Outcome")),
                .init(value: .byHabit, label: String(localized: "By Habit")),
            ],
            selection: $pivot
        )
    }

    private func note(_ board: ConnectionBoard) -> String? {
        guard board.found.isEmpty else { return nil }
        let waiting = board.rows.allSatisfy { row in
            switch row.status {
            case .needsMoreDays, .notRecorded: true
            default: false
            }
        }
        return waiting ? ConnectionLabels.lowDataNote : ConnectionLabels.noneFoundNote
    }

    @ViewBuilder private func byOutcome(_ board: ConnectionBoard) -> some View {
        ForEach(ConnectionBoard.outcomeOrder, id: \.self) { outcome in
            let rows = board.rows(outcome: outcome)
            if !rows.isEmpty {
                Section {
                    ForEach(rows) { row in
                        ConnectionRowView(
                            row: row,
                            title: "\(ConnectionLabels.behaviourName(row.behaviour)) · \(ConnectionLabels.timing(row))",
                            usual: board.usual[outcome],
                            domain: ConnectionAxis.domain(outcome, board: board)
                        )
                    }
                } header: {
                    OutcomeHeader(outcome: outcome, usual: board.usual[outcome])
                }
            }
        }
    }

    @ViewBuilder private func byHabit(_ board: ConnectionBoard) -> some View {
        ForEach(ConnectionBoard.behaviourOrder, id: \.self) { habit in
            let rows = board.rows(behaviour: habit)
            if !rows.isEmpty {
                Section(ConnectionLabels.habitName(habit)) {
                    ForEach(rows) { row in
                        ConnectionRowView(
                            row: row,
                            title: "\(ConnectionLabels.outcomeName(row.outcome)) · \(ConnectionLabels.timing(row))",
                            usual: board.usual[row.outcome],
                            domain: ConnectionAxis.domain(row.outcome, board: board)
                        )
                    }
                }
            }
        }
    }
}

private struct OutcomeHeader: View {
    let outcome: Metric
    let usual: ConnectionBoard.Usual?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ConnectionLabels.outcomeName(outcome))
                .font(.headline)
                .foregroundStyle(.primary)
            if let usual {
                Text(ConnectionLabels.usual(usual, outcome))
                    .font(.caption.monospacedDigit())
            }
        }
        .textCase(nil)
    }
}

/// A found row opens its detail; any other row says why there's nothing to
/// show, without numbers about the outcome.
private struct ConnectionRowView: View {
    let row: ConnectionBoard.Row
    let title: String
    let usual: ConnectionBoard.Usual?
    let domain: ClosedRange<Double>

    var body: some View {
        if row.status.finding != nil {
            NavigationLink(value: ConnectionRoute(id: row.id)) {
                ConnectionComparison(row: row, title: title, usual: usual, domain: domain)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(ConnectionLabels.status(row))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ConnectionLabels.accessibilitySentence(row))
        }
    }
}

/// The two-dot comparison with its numbers. Used in Connections and in
/// Today's *Worth noticing*.
struct ConnectionComparison: View {
    let row: ConnectionBoard.Row
    let title: String
    let usual: ConnectionBoard.Usual?
    let domain: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if let comparison = row.comparison {
                DumbbellView(
                    less: comparison.lessMedian,
                    more: comparison.moreMedian,
                    usualLow: usual?.low,
                    usualHigh: usual?.high,
                    domain: domain
                )
                .frame(height: 22)
                HStack {
                    Text(ConnectionLabels.value(domain.lowerBound, row.outcome))
                    Spacer()
                    Text(ConnectionLabels.value(domain.upperBound, row.outcome))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            if let text = ConnectionLabels.comparison(row) {
                Text(text)
                    .font(.subheadline.monospacedDigit())
            }
            if let evidence = ConnectionLabels.evidence(row) {
                Text(evidence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let latest = row.latest {
                IconText(
                    symbol: latest.side == .less ? "circle" : "circle.fill",
                    text: ConnectionLabels.latest(latest, behaviour: row.behaviour)
                )
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ConnectionLabels.accessibilitySentence(row))
    }
}

/// An icon and its words as one piece of text, so it wraps at larger sizes
/// rather than being cut off. VoiceOver reads only the words.
struct IconText: View {
    let symbol: String
    let text: String

    var body: some View {
        Text("\(Image(systemName: symbol)) \(text)")
            .accessibilityLabel(text)
    }
}

/// A hollow dot (less or none) and a filled dot (more or some) on the
/// outcome's axis, joined by a line, over the usual range. Shape, not
/// colour, tells the groups apart. Decorative: the numbers are in text.
struct DumbbellView: View {
    let less: Double
    let more: Double
    let usualLow: Double?
    let usualHigh: Double?
    let domain: ClosedRange<Double>

    private let radius: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let middle = proxy.size.height / 2
            let lessX = position(less, width: width)
            let moreX = position(more, width: width)
            ZStack {
                Capsule()
                    .fill(.quaternary)
                    .frame(width: width, height: 2)
                    .position(x: width / 2, y: middle)
                if let usualLow, let usualHigh {
                    let lowX = position(usualLow, width: width)
                    let highX = position(usualHigh, width: width)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.tint.opacity(0.15))
                        .frame(width: max(highX - lowX, 2), height: proxy.size.height)
                        .position(x: (lowX + highX) / 2, y: middle)
                }
                Capsule()
                    .fill(.tint.opacity(0.6))
                    .frame(width: abs(moreX - lessX), height: 3)
                    .position(x: (lessX + moreX) / 2, y: middle)
                Circle()
                    .fill(CardStyle.background)
                    .overlay(Circle().strokeBorder(.tint, lineWidth: 2))
                    .frame(width: 2 * radius, height: 2 * radius)
                    .position(x: lessX, y: middle)
                Circle()
                    .fill(.tint)
                    .frame(width: 2 * radius, height: 2 * radius)
                    .position(x: moreX, y: middle)
            }
        }
        .accessibilityHidden(true)
    }

    private func position(_ value: Double, width: CGFloat) -> CGFloat {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return width / 2 }
        let clamped = min(max(value, domain.lowerBound), domain.upperBound)
        return radius + CGFloat((clamped - domain.lowerBound) / span) * (width - 2 * radius)
    }
}

/// One axis per outcome, shared by every row about it, from the person's own
/// spread of values (5th to 95th percentile), so small differences look small.
enum ConnectionAxis {
    static func domain(_ outcome: Metric, board: ConnectionBoard) -> ClosedRange<Double> {
        if outcome.unit == .scale { return 1...5 }
        var values = board.rows(outcome: outcome).compactMap(\.comparison).flatMap { [$0.lessMedian, $0.moreMedian] }
        if let usual = board.usual[outcome] { values += [usual.axisLow, usual.axisHigh, usual.low, usual.high] }
        guard let low = values.min(), let high = values.max(), high > low else {
            let value = values.first ?? 0
            return (value - 1)...(value + 1)
        }
        let padding = (high - low) * 0.05
        return (low - padding)...(high + padding)
    }
}

private struct ConnectionsExplainer: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ConnectionLabels.explainer, id: \.self) { Text($0) }
                } footer: {
                    Text(Copy.shortDisclaimer)
                }
            }
            .navigationTitle("How Connections Works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
