import AppIntents
import SwiftUI
import WidgetKit

/// Widgets and controls only open the app at Quick Log. They show no health
/// data and have no access to Vivra's database (PLAN decision 9).
@main
struct VivraWidgets: WidgetBundle {
    var body: some Widget {
        QuickLogWidget()
        QuickLogControl()
    }
}

struct QuickLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.vivra.quicklog.widget", provider: StaticProvider()) { _ in
            QuickLogWidgetView()
        }
        .configurationDisplayName("Quick Log")
        .description("Open Vivra to log how you feel, drinks and meals.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct StaticEntry: TimelineEntry {
    let date: Date
}

/// One fixed entry: the widget never changes and never reads data.
struct StaticProvider: TimelineProvider {
    func placeholder(in context: Context) -> StaticEntry { StaticEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (StaticEntry) -> Void) {
        completion(StaticEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StaticEntry>) -> Void) {
        completion(Timeline(entries: [StaticEntry(date: .now)], policy: .never))
    }
}

struct QuickLogWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(QuickLogLink.url)
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular:
            Image(systemName: "plus.circle")
                .font(.title)
                .widgetAccentable()
        case .accessoryRectangular:
            Label("Quick Log", systemImage: "plus.circle")
                .font(.headline)
                .widgetAccentable()
        default:
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                Spacer()
                Text("Quick Log")
                    .font(.headline)
                Text("Mood, drinks, meals")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct QuickLogControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.vivra.quicklog.control") {
            ControlWidgetButton(action: OpenQuickLogIntent()) {
                Label("Quick Log", systemImage: "plus.circle")
            }
        }
        .displayName("Vivra Quick Log")
        .description("Open Vivra at Quick Log.")
    }
}
