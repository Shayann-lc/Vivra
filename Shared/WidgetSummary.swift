import Foundation

/// The only health-derived text that leaves Vivra's encrypted database: the
/// day's check-in headline and its first two sentences, for the Daily
/// Summary widget (PLAN Phase 6, decision 9 amended). The app writes it to
/// the App Group container while the widget is installed; the widget only
/// reads it.
struct WidgetSummary: Codable, Equatable {
    /// The check-in's day, "yyyy-MM-dd" in the person's calendar.
    let day: String
    let headline: String
    let sentences: [String]
    let writtenByModel: Bool
}

enum WidgetSummaryFile {
    static let widgetKind = "app.vivra.dailysummary.widget"
    static let fileName = "widget-summary.json"

    /// `group.<app bundle id>`. The widget's bundle id is the app's plus
    /// ".widgets", so both compute the same group.
    static var groupIdentifier: String {
        let bundle = Bundle.main.bundleIdentifier ?? ""
        let app = bundle.hasSuffix(".widgets") ? String(bundle.dropLast(".widgets".count)) : bundle
        return "group." + app
    }

    static var defaultDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    }

    static func read(from directory: URL?) -> WidgetSummary? {
        guard let url = directory?.appendingPathComponent(fileName),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(WidgetSummary.self, from: data)
    }

    /// "yyyy-MM-dd" for `date` in `calendar`, matching `Day.description`.
    static func dayString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// The deep link the Daily Summary widget uses to open Insights.
enum InsightsLink {
    static let url = URL(string: "vivra://insights")!
}
