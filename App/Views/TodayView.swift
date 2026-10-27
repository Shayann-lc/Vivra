import Charts
import Gamification
import InsightEngine
import NarrativeCore
import SwiftUI
import UIKit
import VivraModel

/// Home. Numbers first and compact, no composite scores, no generated text
/// (docs/UX_RESEARCH.md).
struct TodayView: View {
    let model: AppModel
    let openTab: (MainTabView.Selection) -> Void
    @State private var reviewingPermissions = false
    @State private var customizing = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !model.pendingPermissionGroups.isEmpty {
                        NewPermissionsCard { reviewingPermissions = true }
                    }
                    if let progress = model.progress, progress.isWelcomeBack {
                        Label(ProgressCopy.welcomeBack, systemImage: "hand.wave")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.tint.opacity(0.12), in: .rect(cornerRadius: 16))
                    }
                    GlanceCard(glance: model.glance)
                    if let progress = model.progress {
                        ProgressStrip(progress: progress) { openTab(.progress) }
                    }
                    Button {
                        openTab(.log)
                    } label: {
                        Label("Quick Log", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    if let finding = model.glance?.worthNoticing {
                        WorthNoticingCard(finding: finding) { openTab(.insights) }
                    }
                    if model.lastSyncHadFailures {
                        Label(
                            "Some Health data couldn't be read. Vivra will try again next time.",
                            systemImage: "exclamationmark.circle"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    if let snapshot = model.dashboard {
                        ForEach(model.preferences.visibleTodayCards) { card in
                            switch card {
                            case .sleep: SleepCard(snapshot: snapshot)
                            case .heart: HeartCard(snapshot: snapshot, recordings: model.heartRecordings)
                            case .activity: ActivityCard(snapshot: snapshot)
                            case .workouts: WorkoutsCard(snapshot: snapshot)
                            case .logged: TodayLoggedCard(snapshot: snapshot)
                            case .body: BodyCard(snapshot: snapshot)
                            }
                        }
                    } else {
                        ProgressView()
                    }
                    Text(Copy.shortDisclaimer)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            // The grouped style used by every list in iOS: white cards on a
            // grey page, so secondary text keeps its contrast.
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Today")
            .refreshable { await model.sync() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if model.isSyncing { ProgressView() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Customize", systemImage: "slider.horizontal.3") { customizing = true }
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
            }
            .navigationDestination(for: Metric.self) { metric in
                MetricDetailView(model: model, metric: metric)
            }
            .sheet(isPresented: $reviewingPermissions) { PermissionReviewView(model: model) }
            .sheet(isPresented: $customizing) { CardEditorView(preferences: model.preferences) }
            .sheet(isPresented: $showingSettings) { SettingsView(model: model) }
        }
    }
}

/// The latest values next to the person's usual. Each row opens 28 days.
private struct GlanceCard: View {
    let glance: TodayGlance?

    var body: some View {
        Card(title: "At a glance", symbol: "list.bullet.rectangle") {
            if let rows = glance?.rows, !rows.isEmpty {
                ForEach(rows) { row in
                    NavigationLink(value: row.metric) {
                        GlanceRowView(row: row)
                    }
                    .buttonStyle(.plain)
                    if row.id != rows.last?.id { Divider() }
                }
            } else {
                EmptyCardText(text: "No recent sleep, heart or step data yet.")
            }
        }
    }
}

private struct GlanceRowView: View {
    let row: TodayGlance.Row

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(MetricDescriptions.title(row.metric))
                    .font(.subheadline)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(FindingFormatter.format(row.value, row.metric.unit))
                    .font(.body.weight(.semibold).monospacedDigit())
                if let usual = row.usual {
                    Text("usual \(FindingFormatter.format(usual, row.metric.unit))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        if row.isSoFar { return String(localized: "So far today") }
        if row.metric == .sleepDuration {
            return row.daysAgo == 0 ? String(localized: "Last night") : String(localized: "The night before")
        }
        return row.daysAgo == 0 ? String(localized: "Today") : String(localized: "Yesterday")
    }
}

/// One line: today's goal, the run, the level. Opens Progress.
private struct ProgressStrip: View {
    let progress: ProgressSnapshot
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: progress.goalMetToday ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(progress.goalMetToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ProgressCopy.goal(progress))
                        .font(.subheadline.weight(.semibold))
                    Text("\(ProgressCopy.run(progress)) · Level \(progress.level)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding()
            .background(CardStyle.background, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

/// The single most notable finding, in template wording. Opens Insights.
private struct WorthNoticingCard: View {
    let finding: Finding
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Card(title: "Worth noticing", symbol: "eye") {
                Text(TemplateRenderer.sentence(for: finding))
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                if finding.suggestProfessional {
                    Label(Copy.professionalNote, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct Card<Content: View>: View {
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
        .background(CardStyle.background, in: .rect(cornerRadius: 16))
    }
}

struct EmptyCardText: View {
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
                .accessibilityLabel("Sleep by stage over the last 7 days")

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
            .accessibilityLabel("\(title) over the last 7 days")
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

private struct TodayLoggedCard: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        if !snapshot.todayLogged.isEmpty || !snapshot.todayIntake.isEmpty {
            Card(title: "Logged today", symbol: "sun.max") {
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
                .accessibilityLabel("Steps over the last 7 days")
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

enum CardStyle {
    /// The background of Today's cards: the grouped list cell colour.
    static let background = Color(uiColor: .secondarySystemGroupedBackground)
}
