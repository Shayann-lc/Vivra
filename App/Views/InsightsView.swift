import InsightEngine
import NarrativeCore
import SwiftUI
import VivraStore

/// Connections (habits next to outcomes) and Summaries (the reports).
struct InsightsView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                switch model.insightsSection {
                case .connections: ConnectionsView(model: model)
                case .summaries: SummariesView(model: model)
                }
            }
            .navigationTitle("Insights")
            .navigationDestination(for: ConnectionRoute.self) { route in
                ConnectionDetailView(model: model, id: route.id)
            }
            .navigationDestination(for: Metric.self) { metric in
                MetricDetailView(model: model, metric: metric)
            }
        }
    }
}

/// The reports: Why do I feel off today?, the check-in, weekly and monthly
/// summaries, and the Patterns list.
private struct SummariesView: View {
    @Bindable var model: AppModel

    var body: some View {
        List {
            Section {
                InsightsSectionPicker(selection: $model.insightsSection)
            }
            FeelingOffBlock(model: model)
            ReportBlock(model: model, kind: .daily)
            ReportBlock(model: model, kind: .weekly)
            ReportBlock(model: model, kind: .monthly)

            Section {
                NavigationLink {
                    PatternsView(model: model)
                } label: {
                    LabeledContent(
                        "Patterns", value: model.patterns.isEmpty ? "None yet" : "\(model.patterns.count)")
                }
            } footer: {
                Text("Patterns Vivra has found across your last 90 days, with how confident it is in each.")
            }

            Section {
            } footer: {
                Text(Copy.disclaimer)
            }
        }
        .refreshable { await model.refreshAnalysis() }
    }
}

/// "Why do I feel off today?" Things that stood out, never reasons.
private struct FeelingOffBlock: View {
    let model: AppModel

    var body: some View {
        Section {
            Button {
                Task { await model.createReport(.feelingOff) }
            } label: {
                if model.creatingReport == .feelingOff {
                    HStack {
                        ProgressView()
                        Text("Looking at today…")
                    }
                } else {
                    Label("Why do I feel off today?", systemImage: "questionmark.bubble")
                }
            }
            .disabled(model.creatingReport != nil)
        } footer: {
            Text(Copy.feelingOffNote)
        }
        if let report = model.latestReport(.feelingOff),
            Calendar.autoupdatingCurrent.isDateInToday(report.createdAt)
        {
            ReportSection(report: report)
        }
    }
}

/// The latest report of one kind, with a button to create a new one.
private struct ReportBlock: View {
    let model: AppModel
    let kind: ReportKind

    var body: some View {
        if let report = model.latestReport(kind) {
            ReportSection(report: report)
        } else {
            Section(title) {
                Text(introduction).foregroundStyle(.secondary)
            }
        }
        Section {
            Button {
                Task { await model.createReport(kind) }
            } label: {
                if model.creatingReport == kind {
                    HStack {
                        ProgressView()
                        Text("Writing…")
                    }
                } else {
                    Text(model.latestReport(kind) == nil ? "Create \(title)" : "Create a New \(title)")
                }
            }
            .disabled(model.creatingReport != nil)
        }
    }

    private var title: String {
        switch kind {
        case .daily: String(localized: "Check-in")
        case .weekly: String(localized: "Weekly Summary")
        case .monthly: String(localized: "Monthly Summary")
        case .feelingOff: String(localized: "Look at Today")
        }
    }

    private var introduction: String {
        switch kind {
        case .daily:
            String(
                localized:
                    "A short look at last night and today next to your usual, plus anything unusual and one pattern to notice."
            )
        case .weekly:
            String(localized: "A summary of your last 7 days, with patterns and trends from recent weeks.")
        case .monthly:
            String(
                localized:
                    "A deeper look at your last 30 days next to the 30 before, with every pattern and trend Vivra has found."
            )
        case .feelingOff:
            String(localized: "Things in today's data that stood out.")
        }
    }
}

struct ReportSection: View {
    let report: StoredReport

    var body: some View {
        let summary = report.summary
        Section {
            Text(summary.draft.headline)
                .font(.title3.bold())
            if summary.draft.bullets.isEmpty {
                Text(emptyText)
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
            Text(header)
        } footer: {
            Text(generatorNote(summary.generator))
        }
    }

    private var header: String {
        switch report.kind {
        case .daily: String(localized: "Check-in · \(report.createdAt.formatted(date: .abbreviated, time: .shortened))")
        case .weekly: String(localized: "Weekly summary · \(Formatting.dayRange(report.periodStart, report.periodEnd))")
        case .monthly:
            String(localized: "Monthly summary · \(Formatting.dayRange(report.periodStart, report.periodEnd))")
        case .feelingOff: String(localized: "Asked \(report.createdAt.formatted(date: .abbreviated, time: .shortened))")
        }
    }

    private var emptyText: String {
        switch report.kind {
        case .daily:
            String(localized: "There isn't enough recent data for a check-in yet. It needs at least a week of history.")
        case .weekly:
            String(
                localized:
                    "There isn't enough data from the last 7 days yet. Summaries need at least 3 days of a metric.")
        case .monthly:
            String(
                localized:
                    "There isn't enough data from the last 30 days yet. Monthly summaries need 10 days of a metric.")
        case .feelingOff:
            String(
                localized:
                    "Today's data looks close to your usual, and no known pattern applies. That's useful to know too.")
        }
    }

    private func generatorNote(_ generator: NarrativeGenerator) -> String {
        switch generator {
        case .onDeviceModel:
            String(localized: "Written on this iPhone by Apple Intelligence, from numbers Vivra calculated.")
        case .template:
            String(
                localized:
                    "Written from Vivra's templates, from numbers Vivra calculated. Apple Intelligence wasn't available, or its draft didn't pass Vivra's checks."
            )
        }
    }
}

/// Every current pattern and trend, in Vivra's own template wording.
struct PatternsView: View {
    let model: AppModel

    var body: some View {
        List {
            if model.patterns.isEmpty {
                Text(
                    "No patterns yet. Vivra needs at least two weeks of overlapping data, "
                        + "and only shows patterns that are unlikely to be chance."
                )
                .foregroundStyle(.secondary)
            }
            ForEach(model.patterns) { finding in
                VStack(alignment: .leading, spacing: 6) {
                    Text(TemplateRenderer.sentence(for: finding))
                    if let confidence = finding.detail.confidence {
                        Text("\(confidence.rawValue.capitalized) confidence")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            Section {
            } footer: {
                Text(
                    "These are patterns in your data, not causes. Confidence depends on how many days there are, "
                        + "how clear the pattern is, and whether it holds across your history. \(Copy.shortDisclaimer)"
                )
            }
        }
        .navigationTitle("Patterns")
        .task { await model.noteViewedPatterns() }
    }
}
