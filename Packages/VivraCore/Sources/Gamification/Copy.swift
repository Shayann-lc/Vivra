import VivraModel

/// Achievements: consistency (logging over time) and exploring the app.
/// None reward exercise. Raw values may be stored in future; don't rename.
public enum Achievement: String, CaseIterable, Sendable {
    case firstCheckIn
    case threeDays
    case sevenDays
    case thirtyDays
    case hundredDays
    case weekRun
    case monthRun
    case comeback
    case everyKind
    case firstWeeklySummary
    case firstCheckInReport
    case patternSpotter
    case allConnected
    case sharedWithHealth

    public enum Category: String, Sendable {
        case consistency
        case exploring
    }

    public var category: Category {
        switch self {
        case .firstCheckIn, .threeDays, .sevenDays, .thirtyDays, .hundredDays, .weekRun, .monthRun, .comeback:
            .consistency
        case .everyKind, .firstWeeklySummary, .firstCheckInReport, .patternSpotter, .allConnected, .sharedWithHealth:
            .exploring
        }
    }

    public var title: String {
        switch self {
        case .firstCheckIn: "First check-in"
        case .threeDays: "3 days logged"
        case .sevenDays: "7 days logged"
        case .thirtyDays: "30 days logged"
        case .hundredDays: "100 days logged"
        case .weekRun: "A week in a row"
        case .monthRun: "A month in a row"
        case .comeback: "Welcome back"
        case .everyKind: "Full picture"
        case .firstWeeklySummary: "First weekly summary"
        case .firstCheckInReport: "First check-in report"
        case .patternSpotter: "Pattern spotter"
        case .allConnected: "All connected"
        case .sharedWithHealth: "Shared with Health"
        }
    }

    /// How to unlock it, phrased as an invitation.
    public var detail: String {
        switch self {
        case .firstCheckIn: "Save your first Quick Log."
        case .threeDays: "Log on 3 different days."
        case .sevenDays: "Log on 7 different days."
        case .thirtyDays: "Log on 30 different days."
        case .hundredDays: "Log on 100 different days."
        case .weekRun: "Meet your daily goal 7 days in a row. Pauses count."
        case .monthRun: "Meet your daily goal 30 days in a row. Pauses count."
        case .comeback: "Log again after a few days away."
        case .everyKind: "Log mood, energy, stress, a drink, a meal and a note at least once."
        case .firstWeeklySummary: "Create a weekly summary in Insights."
        case .firstCheckInReport: "Create a daily check-in in Insights."
        case .patternSpotter: "Open the Patterns list in Insights."
        case .allConnected: "Answer every Apple Health permission request."
        case .sharedWithHealth: "Turn on saving mood and drinks to Apple Health."
        }
    }

    public var symbol: String {
        switch self {
        case .firstCheckIn: "checkmark.circle"
        case .threeDays, .sevenDays, .thirtyDays, .hundredDays: "calendar"
        case .weekRun, .monthRun: "point.topleft.down.to.point.bottomright.curvepath"
        case .comeback: "hand.wave"
        case .everyKind: "square.grid.3x3"
        case .firstWeeklySummary, .firstCheckInReport: "text.alignleft"
        case .patternSpotter: "sparkle.magnifyingglass"
        case .allConnected: "heart.text.square"
        case .sharedWithHealth: "arrow.triangle.2.circlepath"
        }
    }
}

/// Progress wording. Never mentions loss: a test checks every string against
/// the style guide's banned terms and `lossPhrases`.
public enum ProgressCopy {
    /// Words that frame progress as something that can be lost.
    public static let lossPhrases = [
        "streak", "lost", "lose", "losing", "broke", "broken", "break your", "missed out", "reset", "fail",
        "don't forget", "hurry", "before it's too late",
    ]

    public static func goal(_ snapshot: ProgressSnapshot) -> String {
        if snapshot.goalMetToday {
            return snapshot.target == 1 ? "Today's check-in done" : "Today's goal done"
        }
        let noun = snapshot.target == 1 ? "check-in" : "check-ins"
        return "Today: \(snapshot.checkInsToday) of \(snapshot.target) \(noun)"
    }

    public static func run(_ snapshot: ProgressSnapshot) -> String {
        snapshot.currentRun == 0 ? "Your next check-in starts a run" : "\(snapshot.currentRun)-day run"
    }

    public static func pauses(_ count: Int) -> String {
        switch count {
        case 0: "No pauses saved yet"
        case 1: "1 pause saved"
        default: "\(count) pauses saved"
        }
    }

    public static let pausesExplanation =
        "You earn a pause for every 7 days you meet your goal, and can keep two. A pause covers a day without "
        + "a check-in, so your run continues. You can also log for yesterday in Quick Log."

    public static let welcomeBack = "Welcome back. Nice to see you."

    public static func saved(_ snapshot: ProgressSnapshot, xpEarned: Int) -> String {
        var parts = [snapshot.isWelcomeBack ? "Welcome back" : "Check-in saved"]
        if xpEarned > 0 { parts.append("+\(xpEarned) XP") }
        if snapshot.currentRun > 1 { parts.append("\(snapshot.currentRun)-day run") }
        return parts.joined(separator: " · ")
    }

    public static func status(_ status: DayStatus) -> String {
        switch status {
        case .notStarted: "Before your first check-in"
        case .met: "Goal met"
        case .paused: "Covered by a pause"
        case .missed: "No check-in"
        case .inProgress: "Today"
        }
    }

    /// Every fixed string, for the copy test.
    public static var fixedStrings: [String] {
        [pausesExplanation, welcomeBack] + Achievement.allCases.flatMap { [$0.title, $0.detail] }
            + [DayStatus.notStarted, .met, .paused, .missed, .inProgress].map(status) + ReminderPlan.messages
            + [ReminderPlan.title, pauses(0), pauses(1), pauses(2)]
    }
}
