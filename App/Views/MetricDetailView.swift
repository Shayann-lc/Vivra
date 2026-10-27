import Charts
import InsightEngine
import NarrativeCore
import SwiftUI
import VivraModel

/// 28 days of one metric with the person's usual range shaded, so a number is
/// never shown without its context (docs/UX_RESEARCH.md §4).
struct MetricDetailView: View {
    let model: AppModel
    let metric: Metric

    var body: some View {
        List {
            if let history = model.history(metric), !history.points.isEmpty {
                Section {
                    Chart {
                        if let low = history.usualLow, let high = history.usualHigh,
                            let first = history.points.first, let last = history.points.last
                        {
                            RectangleMark(
                                xStart: .value("Start", date(first.day)),
                                xEnd: .value("End", date(last.day)),
                                yStart: .value("Usual low", plotted(low)),
                                yEnd: .value("Usual high", plotted(high))
                            )
                            .foregroundStyle(.tint.opacity(0.12))
                        }
                        ForEach(history.points) { point in
                            LineMark(x: .value("Day", date(point.day)), y: .value(unitLabel, plotted(point.value)))
                            PointMark(x: .value("Day", date(point.day)), y: .value(unitLabel, plotted(point.value)))
                                .symbolSize(20)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartYAxisLabel(unitLabel)
                    .frame(height: 220)
                    .accessibilityLabel("\(MetricDescriptions.title(metric)) over the last 28 days")
                } footer: {
                    Text("The shaded band is your usual range: the middle 80% of your days.")
                }

                Section {
                    if let latest = history.points.last {
                        LabeledContent("Latest", value: FindingFormatter.format(latest.value, metric.unit))
                    }
                    if let median = history.median {
                        LabeledContent("Your usual", value: FindingFormatter.format(median, metric.unit))
                    }
                    if let low = history.usualLow, let high = history.usualHigh {
                        LabeledContent("Usual range", value: FindingFormatter.range(low, high, metric.unit))
                    }
                    LabeledContent("Days with data", value: "\(history.completeDays) of the last 28")
                }
            } else {
                Section {
                    Text(
                        "No \(MetricDescriptions.title(metric).lowercased()) in the last 28 days. \(Copy.healthAccessHint)"
                    )
                    .foregroundStyle(.secondary)
                }
            }

            Section("About this measurement") {
                Text(MetricDescriptions.description(metric))
                Text(Copy.shortDisclaimer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(MetricDescriptions.title(metric))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func date(_ day: Day) -> Date {
        Calendar.autoupdatingCurrent.date(from: DateComponents(year: day.year, month: day.month, day: day.day)) ?? .now
    }

    /// Sleep plots in hours; everything else in its own unit.
    private func plotted(_ value: Double) -> Double {
        metric.unit == .seconds ? value / 3600 : value
    }

    private var unitLabel: String {
        switch metric.unit {
        case .seconds: "Hours"
        case .beatsPerMinute: "bpm"
        case .milliseconds: "ms"
        case .steps: "Steps"
        case .minutes: "Minutes"
        case .scale: "1–5"
        case .kilocalories: "kcal"
        case .meters: "Metres"
        case .percent: "%"
        case .milliliters: "mL"
        case .milligrams: "mg"
        case .kilograms: "kg"
        case .degreesCelsius: "°C"
        case .breathsPerMinute: "Breaths/min"
        default: "Value"
        }
    }
}
