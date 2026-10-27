import Gamification
import SwiftUI
import VivraModel

/// Rewards logging, never exercise. Missed days are drawn neutrally, and there
/// is no loss language anywhere (docs/UX_RESEARCH.md §5).
struct ProgressScreen: View {
    let model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if let progress = model.progress {
                    LevelSection(progress: progress)
                    RunSection(progress: progress)
                    GoalSection(model: model, progress: progress)
                    AchievementsSection(progress: progress)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Progress")
            .task { await model.refreshProgress() }
        }
    }
}

private struct LevelSection: View {
    let progress: ProgressSnapshot

    var body: some View {
        Section {
            HStack {
                Text("Level \(progress.level)")
                    .font(.title2.bold())
                Spacer()
                Text("\(progress.xp) XP")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(
                value: Double(progress.xp - progress.levelStartXP),
                total: Double(progress.nextLevelXP - progress.levelStartXP)
            ) {
                Text("\(progress.nextLevelXP - progress.xp) XP to level \(progress.level + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text(
                "XP comes from logging: 10 for your first check-in of the day, 5 more for each other kind you log, and 5 for meeting your goal."
            )
        }
    }
}

private struct RunSection: View {
    let progress: ProgressSnapshot

    var body: some View {
        Section {
            HStack(spacing: 6) {
                ForEach(progress.lastSevenDays) { day in
                    VStack(spacing: 4) {
                        DayDot(status: day.status)
                        Text(Formatting.weekday(day.day))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(Formatting.weekday(day.day)): \(ProgressCopy.status(day.status))")
                }
            }
            .padding(.vertical, 4)
            LabeledContent("Current run", value: ProgressCopy.run(progress))
            LabeledContent("Pauses", value: ProgressCopy.pauses(progress.pausesHeld))
            LabeledContent("Days logged in total", value: "\(progress.totalDaysLogged)")
            LabeledContent("Longest run", value: "\(progress.longestRun) days")
        } header: {
            Text("Last 7 days")
        } footer: {
            Text(ProgressCopy.pausesExplanation)
        }
    }
}

private struct DayDot: View {
    let status: DayStatus

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.secondary.opacity(0.4), lineWidth: 1.5)
            switch status {
            case .met:
                Circle().fill(.tint)
                Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.white)
            case .paused:
                Circle().fill(.tint.opacity(0.35))
                Image(systemName: "pause.fill").font(.caption2).foregroundStyle(.tint)
            case .inProgress:
                Circle().strokeBorder(.tint, style: StrokeStyle(lineWidth: 1.5, dash: [3]))
            case .missed, .notStarted:
                EmptyView()
            }
        }
        .frame(width: 28, height: 28)
    }
}

private struct GoalSection: View {
    let model: AppModel
    let progress: ProgressSnapshot

    var body: some View {
        Section {
            LabeledContent("Today", value: ProgressCopy.goal(progress))
            Picker(
                "Daily goal",
                selection: Binding(get: { progress.target }, set: { target in Task { await model.setGoal(target) } })
            ) {
                ForEach(Array(ProgressRules.targetRange), id: \.self) { target in
                    Text(target == 1 ? "1 check-in" : "\(target) check-ins").tag(target)
                }
            }
        } header: {
            Text("Daily goal")
        } footer: {
            Text("A check-in is one Quick Log save. Changing your goal starts today; past days keep the goal they had.")
        }
    }
}

private struct AchievementsSection: View {
    let progress: ProgressSnapshot

    var body: some View {
        Section("Achievements") {
            ForEach(progress.achievements) { state in
                HStack(spacing: 12) {
                    Image(systemName: state.achievement.symbol)
                        .font(.title3)
                        .frame(width: 32)
                        .foregroundStyle(state.isUnlocked ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.achievement.title)
                            .font(.subheadline.weight(state.isUnlocked ? .semibold : .regular))
                        Text(state.unlockedOn.map { "Earned \(Formatting.shortDate($0))" } ?? state.achievement.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
