import Charts
import InsightEngine
import NarrativeCore
import SwiftUI
import VivraModel

struct DashboardView: View {
    let model: AppModel
    @State private var reviewingPermissions = false

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
                    if !model.pendingPermissionGroups.isEmpty {
                        NewPermissionsCard { reviewingPermissions = true }
                    }
                    if let snapshot = model.dashboard {
                        TodayCard(snapshot: snapshot)
                        SleepCard(snapshot: snapshot)
                        HeartCard(snapshot: snapshot, recordings: model.heartRecordings)
                        ActivityCard(snapshot: snapshot)
                        WorkoutsCard(snapshot: snapshot)
                        BodyCard(snapshot: snapshot)
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
            .sheet(isPresented: $reviewingPermissions) { PermissionReviewView(model: model) }
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
    let recordings: HeartRecordings

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
            if !recordings.isEmpty {
                NavigationLink {
                    HeartRecordingsView(recordings: recordings)
                } label: {
                    Label("Heart recordings from Apple Health", systemImage: "waveform.path.ecg")
                        .font(.subheadline)
                }
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

private struct NewPermissionsCard: View {
    let action: () -> Void

    var body: some View {
        Card(title: "More Health data available", symbol: "sparkles") {
            Text("Vivra can now read activity, State of Mind, nutrition, body measurements and heart recordings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Review Access", action: action)
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct TodayCard: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        if !snapshot.todayLogged.isEmpty || !snapshot.todayIntake.isEmpty {
            Card(title: "Today", symbol: "sun.max") {
                let items = rows
                ForEach(items, id: \.0) { label, value in
                    LabeledContent(label, value: value)
                        .font(.subheadline)
                }
            }
        }
    }

    private var rows: [(String, String)] {
        var rows: [(String, String)] = []
        let labels: [(Metric, String)] = [
            (.mood, "Mood"), (.energyLevel, "Energy"), (.stressLevel, "Stress"), (.water, "Water"),
            (.caffeine, "Caffeine (estimated)"), (.alcohol, "Alcohol"),
        ]
        for (metric, label) in labels {
            if let value = snapshot.todayLogged[metric] ?? snapshot.todayIntake[metric] {
                rows.append((label, FindingFormatter.format(value, metric.unit)))
            }
        }
        return rows
    }
}

private struct ActivityCard: View {
    let snapshot: DashboardSnapshot

    private struct Bar: Identifiable {
        let day: Day
        let steps: Double
        var id: Day { day }
    }

    var body: some View {
        Card(title: "Activity", symbol: "figure.walk") {
            let bars = snapshot.activity.compactMap { day in day.steps.map { Bar(day: day.day, steps: $0) } }
            if bars.isEmpty {
                EmptyCardText(text: "No steps recorded in the last 7 days.")
            } else {
                Text("Steps")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Chart(bars) { bar in
                    BarMark(x: .value("Day", Formatting.weekday(bar.day)), y: .value("Steps", bar.steps))
                }
                .chartXScale(domain: snapshot.days.map { Formatting.weekday($0) })
                .frame(height: 140)
            }
            if let today = snapshot.activity.last(where: { $0.day == snapshot.days.last }),
                let minutes = today.exerciseMinutes
            {
                Text("Exercise today: \(FindingFormatter.format(minutes, .minutes))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct BodyCard: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        if !snapshot.latestBody.isEmpty {
            Card(title: "Body", symbol: "figure.stand") {
                let labels: [(Metric, String)] = [
                    (.weight, "Weight"), (.bodyFat, "Body fat"), (.respiratoryRate, "Respiratory rate"),
                    (.bloodOxygen, "Blood oxygen"), (.wristTemperature, "Sleeping wrist temperature"),
                ]
                ForEach(labels.filter { snapshot.latestBody[$0.0] != nil }, id: \.0) { metric, label in
                    let reading = snapshot.latestBody[metric]!
                    LabeledContent(label) {
                        VStack(alignment: .trailing) {
                            Text(FindingFormatter.format(reading.value, metric.unit))
                            Text(Formatting.weekday(reading.day))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}

struct HeartRecordingsView: View {
    let recordings: HeartRecordings

    var body: some View {
        List {
            Section {
                Text(Copy.heartRecordingsNote)
                    .foregroundStyle(.secondary)
                Label(Copy.professionalNote, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !recordings.ecgs.isEmpty {
                Section("ECG recordings") {
                    ForEach(recordings.ecgs) { ecg in
                        LabeledContent(
                            ecg.date.formatted(date: .abbreviated, time: .shortened),
                            value: Formatting.ecgClassification(ecg.classification)
                        )
                    }
                }
            }
            if !recordings.irregularRhythmDates.isEmpty {
                Section("Irregular rhythm notifications") {
                    ForEach(recordings.irregularRhythmDates, id: \.self) { date in
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
        }
        .navigationTitle("Heart Recordings")
    }
}
