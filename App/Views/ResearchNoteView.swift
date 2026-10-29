import Evidence
import SwiftUI
import VivraModel

/// A reviewed research note about groups of people, shown word for word
/// beside a sentence (PLAN decision 11). Tapping it opens its sources.
struct ResearchNoteView: View {
    /// Nil when a saved note's card has since been withdrawn.
    let card: EvidenceCard?
    /// Shown above the card when the person's own data goes the other way.
    var differs = false
    @State private var showingSources = false

    var body: some View {
        if let card {
            Button {
                showingSources = true
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.tint)
                        .frame(width: 3)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(EvidenceText.heading)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if card.status != .ready {
                            IconText(symbol: "pencil.circle", text: EvidenceText.draftLabel)
                                .font(.caption.weight(.semibold))
                        }
                        if differs {
                            Text(EvidenceText.differs)
                                .font(.footnote)
                        }
                        Text(card.statement)
                            .font(.footnote)
                        Text(Self.attribution(card))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the sources")
            .sheet(isPresented: $showingSources) { EvidenceSourcesView(card: card) }
        } else {
            Text(EvidenceText.withdrawn)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    enum Display {
        case card(EvidenceCard)
        /// The card has since been withdrawn.
        case withdrawn

        var card: EvidenceCard? {
            if case .card(let card) = self { return card }
            return nil
        }
    }

    /// How to show a saved note. Nil when this build doesn't show its card
    /// (a draft saved by a Debug build, opened in Release).
    static func display(_ note: ResearchNote) -> Display? {
        guard let card = AppModel.evidence.card(id: note.cardID), card.status != .excluded else { return .withdrawn }
        return AppModel.evidence.shownStatuses.contains(card.status) ? .card(card) : nil
    }

    /// "Pietilä et al., 2018 · Some studies".
    static func attribution(_ card: EvidenceCard) -> String {
        let citations = card.sources.map(\.shortCitation).joined(separator: "; ")
        return "\(citations) · \(EvidenceText.strength(card.strength))"
    }
}

/// Everything behind a research note: who was studied, caveats, how much
/// research there is, and each source with its link and licence.
struct EvidenceSourcesView: View {
    let card: EvidenceCard
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(card.statement)
                    if card.status != .ready {
                        IconText(symbol: "pencil.circle", text: EvidenceText.draftLabel)
                            .font(.footnote.weight(.semibold))
                    }
                } footer: {
                    Text(EvidenceText.footer)
                }
                Section("Who Was Studied") {
                    Text(card.population)
                }
                Section("Keep in Mind") {
                    ForEach(card.caveats, id: \.self) { Text($0) }
                }
                Section("How Much Research") {
                    Text(EvidenceText.strength(card.strength))
                }
                Section {
                    ForEach(card.sources, id: \.url) { source in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(source.citation)
                                .font(.subheadline)
                            Text(source.design)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text("Licence: \(source.licence)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if let url = URL(string: source.url) {
                                Link(destination: url) {
                                    Text(source.doi.map { "doi:\($0)" } ?? source.url)
                                        .font(.footnote)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Sources")
                } footer: {
                    Text(reviewNote)
                }
            }
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var reviewNote: String {
        if let day = card.reviewedOn, card.status == .ready {
            return String(localized: "Reviewed \(Formatting.shortDate(day)). Written in Vivra's own words.")
        }
        return String(
            localized: "Checked against its sources and waiting for review. Written in Vivra's own words.")
    }
}
