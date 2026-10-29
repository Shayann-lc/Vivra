import Charts
import InsightEngine
import NarrativeCore
import SwiftUI
import VivraModel

/// The days behind one connection: both groups' numbers, each day as a dot,
/// the last 28 days, the template sentence and how it was worked out.
struct ConnectionDetailView: View {
    let model: AppModel
    let id: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        List {
            if let board = model.connections, let row = board.row(id: id), let finding = row.status.finding,
                let comparison = row.comparison, let groups = ConnectionLabels.groups(finding)
            {
                Section {
                    Text(ConnectionLabels.title(row))
                        .font(.headline)
                    numbers(row, comparison: comparison, groups: groups)
                    Text(ConnectionLabels.confidenceText(comparison.confidence))
                        .font(.subheadline)
                    if let latest = row.latest {
                        Label(
                            ConnectionLabels.latest(latest, behaviour: row.behaviour),
                            systemImage: latest.side == .less ? "circle" : "circle.fill"
                        )
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let days = model.connectionDays(finding) {
                    EachDaySection(row: row, days: days, groups: groups, usual: board.usual[row.outcome])
                    TimelineSection(row: row, days: days)
                }

                Section("In Words") {
                    Text(TemplateRenderer.sentence(for: finding))
                }

                Section {
                    ForEach(ConnectionLabels.method(finding), id: \.self) { Text($0) }
                } header: {
                    Text("How This Was Worked Out")
                } footer: {
                    Text(ConnectionLabels.footer)
                }

                Section {
                    NavigationLink(value: row.behaviour.metric) {
                        Text(MetricDescriptions.title(row.behaviour.metric))
                    }
                    NavigationLink(value: row.outcome) {
                        Text(MetricDescriptions.title(row.outcome))
                    }
                } header: {
                    Text("Last 28 Days of Each")
                } footer: {
                    Text(Copy.shortDisclaimer)
                }
            } else {
                Text("This connection isn't in your latest data. Pull down on Connections to refresh.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Connection")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func numbers(
        _ row: ConnectionBoard.Row,
        comparison: ConnectionBoard.Comparison,
        groups: (less: String, more: String)
    ) -> some View {
        let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            GroupColumn(
                symbol: "circle",
                label: groups.less,
                value: ConnectionLabels.value(comparison.lessMedian, row.outcome),
                days: comparison.lessDays
            )
            GroupColumn(
                symbol: "circle.fill",
                label: groups.more,
                value: ConnectionLabels.value(comparison.moreMedian, row.outcome),
                days: comparison.moreDays
            )
        }
    }
}

private struct GroupColumn: View {
    let symbol: String
    let label: String
    let value: String
    let days: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Wraps rather than truncating at larger text sizes.
            Label(label, systemImage: symbol)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .fixedSize(horizontal: false, vertical: true)
            Text("\(days) days")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Each paired day as a dot in its group's lane, with each group's median
/// and the usual range behind.
private struct EachDaySection: View {
    let row: ConnectionBoard.Row
    let days: ConnectionDays
    let groups: (less: String, more: String)
    let usual: ConnectionBoard.Usual?

    private let between = String(localized: "In between")

    private func lane(_ group: ConnectionDays.Group) -> String {
        switch group {
        case .less: groups.less
        case .between: between
        case .more: groups.more
        }
    }

    private var lanes: [String] {
        days.pairs(in: .between).isEmpty ? [groups.more, groups.less] : [groups.more, between, groups.less]
    }

    private func plotted(_ value: Double) -> Double { ChartUnits.plotted(value, row.outcome) }

    private struct Median: Identifiable {
        let lane: String
        let value: Double
        var id: String { lane }
    }

    private var medians: [Median] {
        guard let comparison = row.comparison else { return [] }
        return [
            Median(lane: groups.less, value: comparison.lessMedian),
            Median(lane: groups.more, value: comparison.moreMedian),
        ]
    }

    var body: some View {
        Section {
            Chart {
                if let usual {
                    ForEach(lanes, id: \.self) { lane in
                        RectangleMark(
                            xStart: .value("Usual low", plotted(usual.low)),
                            xEnd: .value("Usual high", plotted(usual.high)),
                            y: .value("Group", lane)
                        )
                        .foregroundStyle(.tint.opacity(0.12))
                    }
                }
                ForEach(days.pairs) { pair in
                    if pair.group == .less {
                        PointMark(
                            x: .value(ChartUnits.label(row.outcome), plotted(pair.outcome)),
                            y: .value("Group", lane(pair.group))
                        )
                        .symbol {
                            Circle()
                                .strokeBorder(.tint, lineWidth: 1.5)
                                .frame(width: 8, height: 8)
                        }
                    } else {
                        PointMark(
                            x: .value(ChartUnits.label(row.outcome), plotted(pair.outcome)),
                            y: .value("Group", lane(pair.group))
                        )
                        .symbolSize(30)
                        .foregroundStyle(pair.group == .more ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    }
                }
                ForEach(medians) { median in
                    PointMark(
                        x: .value(ChartUnits.label(row.outcome), plotted(median.value)),
                        y: .value("Group", median.lane)
                    )
                    .symbol(BasicChartSymbolShape.diamond)
                    .symbolSize(160)
                    .foregroundStyle(.primary)
                }
            }
            .chartYScale(domain: lanes)
            .chartXScale(domain: .automatic(includesZero: false))
            .chartXAxisLabel(ChartUnits.label(row.outcome))
            .frame(height: CGFloat(lanes.count) * 56 + 40)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Each day, by group")
            .accessibilityValue(ConnectionLabels.comparison(row) ?? "")
        } header: {
            Text("Each Day")
        } footer: {
            Text(
                "Each dot is one day. The diamonds mark each group's median, and the shaded band is your usual range. "
                    + "Days in between aren't part of the comparison."
            )
        }
    }
}

/// The last 28 days of the habit (bars) and the outcome (line), lined up so
/// each outcome sits under the day it's compared with.
private struct TimelineSection: View {
    let row: ConnectionBoard.Row
    let days: ConnectionDays

    private var dateRange: ClosedRange<Date> {
        let first = days.timeline.first.map { ChartUnits.date($0.day) } ?? .now
        let last = days.timeline.last.map { ChartUnits.date($0.day) } ?? .now
        return first...max(first, last)
    }

    var body: some View {
        let behaviour = row.behaviour.metric
        Section {
            Chart(days.timeline) { day in
                if let value = day.behaviour {
                    BarMark(
                        x: .value("Day", ChartUnits.date(day.day), unit: .day),
                        y: .value(ChartUnits.label(behaviour), ChartUnits.plotted(value, behaviour))
                    )
                    .foregroundStyle(.tint.opacity(0.6))
                }
            }
            .chartXScale(domain: dateRange)
            .chartYAxisLabel(ConnectionLabels.habitName(behaviour))
            .frame(height: 110)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(ConnectionLabels.habitName(behaviour)) over the last 28 days")

            Chart(days.timeline) { day in
                if let value = day.outcome {
                    LineMark(
                        x: .value("Day", ChartUnits.date(day.day), unit: .day),
                        y: .value(ChartUnits.label(row.outcome), ChartUnits.plotted(value, row.outcome))
                    )
                    PointMark(
                        x: .value("Day", ChartUnits.date(day.day), unit: .day),
                        y: .value(ChartUnits.label(row.outcome), ChartUnits.plotted(value, row.outcome))
                    )
                    .symbolSize(20)
                }
            }
            .chartXScale(domain: dateRange)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxisLabel(ConnectionLabels.outcomeName(row.outcome))
            .frame(height: 140)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(ConnectionLabels.outcomeName(row.outcome)) over the same days")
        } header: {
            Text("Last 28 Days")
        } footer: {
            Text(ConnectionLabels.timelineNote(row))
        }
    }
}
