import InsightEngine
import NarrativeCore
import SwiftUI
import VivraStore

struct SummaryView: View {
    let model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if let report = model.latestReport {
                    ReportSection(report: report)
                } else {
                    Section {
                        Text(
                            "Vivra can write a short summary of your last 7 days, with any patterns from recent months. "
                                + "It's written on this iPhone and checked so it only uses numbers Vivra has calculated."
                        )
                        .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        Task { await model.createWeeklySummary() }
                    } label: {
                        if model.isCreatingSummary {
                            HStack {
                                ProgressView()
                                Text("Writing summary…")
                            }
                        } else {
                            Text(model.latestReport == nil ? "Create Summary" : "Create a New Summary")
                        }
                    }
                    .disabled(model.isCreatingSummary)
                } footer: {
                    Text(Copy.disclaimer)
                }
            }
            .navigationTitle("Weekly Summary")
        }
    }
}

private struct ReportSection: View {
    let report: StoredReport

    var body: some View {
        let summary = report.summary
        Section {
            Text(summary.draft.headline)
                .font(.title3.bold())
            if summary.draft.bullets.isEmpty {
                Text("There isn't enough data from the last 7 days yet. Summaries need at least 3 days of a metric.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(summary.draft.bullets.enumerated()), id: \.offset) { _, bullet in
                VStack(alignment: .leading, spacing: 6) {
                    Text(bullet.text)
                    if summary.findings.first(where: { $0.id == bullet.findingID })?.suggestProfessional == true {
                        Label(Copy.professionalNote, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(Formatting.dayRange(report.periodStart, report.periodEnd))
        } footer: {
            Text(generatorNote(summary.generator))
        }
    }

    private func generatorNote(_ generator: NarrativeGenerator) -> String {
        switch generator {
        case .onDeviceModel:
            "Written on this iPhone by Apple Intelligence, from numbers Vivra calculated."
        case .template:
            "Written from Vivra's templates, from numbers Vivra calculated. "
                + "Apple Intelligence wasn't available, or its draft didn't pass Vivra's checks."
        }
    }
}
