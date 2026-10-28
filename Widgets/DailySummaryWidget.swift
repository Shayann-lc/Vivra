import SwiftUI
import WidgetKit

/// Today's check-in headline and first two sentences (PLAN Phase 6). Reads
/// only the small file the app writes to the App Group container; it has no
/// database access. The text is redacted while the phone is locked.
struct DailySummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSummaryFile.widgetKind, provider: DailySummaryProvider()) { entry in
            DailySummaryWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Summary")
        .description("Today's check-in from Vivra. Hidden while your iPhone is locked.")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}

struct DailySummaryEntry: TimelineEntry {
    let date: Date
    /// Nil when there's no check-in for today yet.
    let summary: WidgetSummary?
}

struct DailySummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailySummaryEntry {
        DailySummaryEntry(
            date: .now,
            summary: WidgetSummary(
                day: "", headline: "Today's check-in",
                sentences: ["Last night you slept 7h 10m.", "Your resting heart rate today was 57 bpm."],
                writtenByModel: false))
    }

    func getSnapshot(in context: Context, completion: @escaping (DailySummaryEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: .now))
    }

    /// One entry now, refreshed at midnight so yesterday's text is never
    /// shown as today's. The app reloads the widget when it writes a new
    /// check-in.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DailySummaryEntry>) -> Void) {
        let now = Date.now
        let midnight = Calendar.autoupdatingCurrent.nextDate(
            after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime)
        completion(Timeline(entries: [entry(at: now)], policy: midnight.map { .after($0) } ?? .atEnd))
    }

    private func entry(at date: Date) -> DailySummaryEntry {
        let today = WidgetSummaryFile.dayString(date, calendar: .autoupdatingCurrent)
        let summary = WidgetSummaryFile.read(from: WidgetSummaryFile.defaultDirectory)
        return DailySummaryEntry(date: date, summary: summary?.day == today ? summary : nil)
    }
}

struct DailySummaryWidgetView: View {
    let entry: DailySummaryEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(InsightsLink.url)
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder private var content: some View {
        if let summary = entry.summary {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.headline)
                        .font(.headline)
                        .widgetAccentable()
                    if let first = summary.sentences.first {
                        Text(first).font(.caption)
                    }
                }
                .privacySensitive()
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Label(summary.headline, systemImage: "text.alignleft")
                        .font(.headline)
                        .lineLimit(1)
                    Text(summary.sentences.joined(separator: " "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .privacySensitive()
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("Daily Summary", systemImage: "text.alignleft")
                    .font(.headline)
                Text("Open Vivra for today's check-in.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
