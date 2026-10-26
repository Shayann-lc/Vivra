import Charts
import InsightEngine
import SwiftUI
import VivraModel

struct DashboardView: View {
    let model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if model.lastSyncHadFailures {
                        Label(
                            "Some Health data couldn't be read. Vivra will try again next time.",
                            systemImage: "exclamationmark.circle"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    if let snapshot = model.dashboard {
                        SleepCard(snapshot: snapshot)
                        HeartCard(snapshot: snapshot)
                        WorkoutsCard(snapshot: snapshot)
                    } else {
                        ProgressView()
                    }
                    Text(Copy.shortDisclaimer)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Last 7 Days")
            .refreshable { await model.sync() }
            .toolbar {
                if model.isSyncing { ProgressView() }
            }
        }
    }
}

private struct Card<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }
}

private struct EmptyCardText: View {
    let text: String

    var body: some View {
        Text("\(text) \(Copy.healthAccessHint)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

private struct SleepCard: View {
    let snapshot: DashboardSnapshot

    private struct Bar: Identifiable {
        let day: String
        let stage: String
        let hours: Double
        var id: String { day + stage }
    }

    private var bars: [Bar] {
        snapshot.sleep.flatMap { night -> [Bar] in
            let label = Formatting.weekday(night.day)
            let staged: [(SleepStage, String)] = [(.deep, "Deep"), (.core, "Core"), (.rem, "REM")]
            let stagedBars = staged.compactMap { stage, name in
                night.stages[stage].map { Bar(day: label, stage: name, hours: $0 / 3600) }
            }
            return stagedBars.isEmpty ? [Bar(day: label, stage: "Asleep", hours: night.asleep / 3600)] : stagedBars
        }
    }

    var body: some View {
        Card(title: "Sleep", symbol: "bed.double") {
            if snapshot.sleep.isEmpty {
                EmptyCardText(text: "No sleep recorded in the last 7 days.")
            } else {
                Chart(bars) { bar in
                    BarMark(x: .value("Day", bar.day), y: .value("Hours", bar.hours))
                        .foregroundStyle(by: .value("Stage", bar.stage))
                }
                .chartXScale(domain: snapshot.days.map { Formatting.weekday($0) })
                .chartYAxisLabel("Hours")
                .frame(height: 180)

                if let last = snapshot.sleep.last {
                    Text("Most recent night: \(Formatting.duration(last.asleep)) asleep")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct HeartCard: View {
    let snapshot: DashboardSnapshot

    private struct Point: Identifiable {
        let day: Day
        let value: Double
        var id: Day { day }
    }

    var body: some View {
        Card(title: "Heart", symbol: "heart") {
            if snapshot.heart.isEmpty {
                EmptyCardText(text: "No resting heart rate or heart rate variability in the last 7 days.")
            } else {
                metricChart(
                    title: "Resting heart rate (bpm)",
                    points: snapshot.heart.compactMap { day in
                        day.restingHeartRate.map { Point(day: day.day, value: $0) }
                    }
                )
                metricChart(
                    title: "Heart rate variability, SDNN (ms)",
                    points: snapshot.heart.compactMap { day in
                        day.heartRateVariability.map { Point(day: day.day, value: $0) }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func metricChart(title: String, points: [Point]) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        if points.isEmpty {
            Text("No data in the last 7 days.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Chart(points) { point in
                LineMark(x: .value("Day", Formatting.weekday(point.day)), y: .value(title, point.value))
                PointMark(x: .value("Day", Formatting.weekday(point.day)), y: .value(title, point.value))
            }
            .chartXScale(domain: snapshot.days.map { Formatting.weekday($0) })
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 120)
        }
    }
}

private struct WorkoutsCard: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        Card(title: "Workouts", symbol: "figure.run") {
            if snapshot.workouts.isEmpty {
                EmptyCardText(text: "No workouts recorded in the last 7 days.")
            } else {
                ForEach(snapshot.workouts) { workout in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Formatting.workoutName(workout.activityType))
                            .font(.subheadline.bold())
                        Text(details(for: workout))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if workout.id != snapshot.workouts.last?.id { Divider() }
                }
            }
        }
    }

    private func details(for workout: Workout) -> String {
        var parts = [
            workout.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()),
            Formatting.duration(workout.duration),
        ]
        if let energy = workout.activeEnergyKilocalories {
            parts.append(
                Measurement(value: energy, unit: UnitEnergy.kilocalories).formatted(
                    .measurement(width: .abbreviated, usage: .workout)))
        }
        if let distance = workout.distanceMeters {
            parts.append(
                Measurement(value: distance, unit: UnitLength.meters).formatted(
                    .measurement(width: .abbreviated, usage: .road)))
        }
        return parts.joined(separator: " · ")
    }
}
