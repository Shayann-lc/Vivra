import InsightEngine
import VivraModel

/// What a card matches. Exact keys from the engine only: no text search.
public enum EvidenceKey: Hashable, Codable, Sendable {
    /// A `PatternCatalog` correlation: X on day t, Y on day t + lag.
    case correlation(x: Metric, y: Metric, lag: Int)
    /// A group difference: the outcome on days with the condition.
    case groupDifference(Condition, outcome: Metric)
    /// Background about a measure, for its detail screen.
    case metricContext(Metric)

    /// The pattern a finding reports, if it's a pattern.
    public init?(_ finding: Finding) {
        switch finding.detail {
        case .correlation(let correlation):
            self = .correlation(x: correlation.x, y: correlation.y, lag: correlation.lag)
        case .groupDifference(let difference):
            self = .groupDifference(difference.condition, outcome: difference.outcome)
        default: return nil
        }
    }
}

/// What studies found. For correlations: the outcome as the behaviour rises.
/// For group differences: the outcome on days with the condition.
public enum EvidenceDirection: String, Codable, Sendable {
    case higher
    case lower
    /// Studies found no consistent difference.
    case noConsistentDifference
    /// Studies disagree, or measured something that went different ways.
    case mixed
    /// Background cards, which have no direction.
    case notApplicable

    /// The direction a person's own pattern shows.
    init?(observedIn finding: Finding) {
        let difference: Double
        switch finding.detail {
        case .correlation(let correlation): difference = correlation.highGroupMedianY - correlation.lowGroupMedianY
        case .groupDifference(let group): difference = group.withConditionMedian - group.withoutConditionMedian
        default: return nil
        }
        guard difference != 0 else { return nil }
        self = difference > 0 ? .higher : .lower
    }
}

/// How a person's pattern compares with a card.
public enum EvidenceAgreement: String, Codable, Sendable {
    /// The same direction.
    case agrees
    /// The research is mixed or found no consistent difference.
    case researchMixed
    /// The opposite direction.
    case differs
}

/// How much evidence there is. Shown with neutral labels (`EvidenceText`).
public enum EvidenceStrength: String, Codable, Sendable, Comparable {
    /// Two or more systematic reviews or meta-analyses, or one large one, that agree.
    case consistent
    /// One systematic review with some inconsistency, or one large cohort.
    case moderate
    /// Small trials, pilot studies or a single small cohort.
    case limited
    /// Reviews or trials that disagree.
    case mixed

    private var rank: Int {
        switch self {
        case .consistent: 3
        case .moderate: 2
        case .limited: 1
        case .mixed: 0
        }
    }

    public static func < (lhs: EvidenceStrength, rhs: EvidenceStrength) -> Bool { lhs.rank < rhs.rank }
}

public enum EvidenceStatus: String, Codable, Sendable {
    /// Signed off by the owner in `docs/EVIDENCE.md`. Shown in every build.
    case ready
    /// Drafted and checked against its sources, waiting for sign-off. Shown
    /// only in Debug builds, labelled as a draft.
    case draft
    /// Kept for the record. Never shown.
    case referenceOnly
    /// Deliberately not shown (for example, a clinical topic). The reason is in `note`.
    case excluded
}

public enum EvidenceSurface: String, Codable, Sendable {
    /// Under a pattern sentence in summaries, and in a connection's detail.
    case patternNote
    /// "What research says" in metric detail.
    case metricDetail
}

/// How closely the card's measure matches Vivra's metric.
public enum MatchQuality: String, Codable, Sendable {
    /// The same measure, for example sleep duration and total sleep time.
    case direct
    /// A related measure, for example rated sleep quality and sleep duration.
    /// The statement says what was measured.
    case indirect
}

public struct EvidenceSource: Codable, Sendable, Equatable {
    public enum Checked: String, Codable, Sendable {
        case abstract
        case fullText
    }

    /// "Pietilä J, Helander E, Korhonen I, et al."
    public let authors: String
    public let title: String
    public let journal: String
    public let year: Int
    /// "5(1):e23"
    public let volumeAndPages: String
    public let doi: String?
    /// Always set: the DOI link when there is one.
    public let url: String
    /// "Observational study; 4,098 adults; 12,411 nights". Citation detail,
    /// shown only in the Sources sheet.
    public let design: String
    /// "CC BY 4.0", or "© Elsevier; nothing copied".
    public let licence: String
    /// What the statement was checked against.
    public let checked: Checked

    /// "Pietilä et al., 2018".
    public var shortCitation: String {
        let first = authors.split(separator: " ").first.map(String.init) ?? authors
        let etAl = authors.contains(",") ? " et al." : ""
        return "\(first)\(etAl), \(year)"
    }

    /// The full reference.
    public var citation: String {
        "\(authors) \(title). \(journal). \(year);\(volumeAndPages)." + (doi.map { " doi:\($0)" } ?? "")
    }
}

public struct EvidenceCard: Codable, Sendable, Equatable, Identifiable {
    /// Stable: saved reports keep it.
    public let id: String
    /// Goes up whenever the text or sources change.
    public let revision: Int
    public let matches: [EvidenceKey]
    public let matchQuality: MatchQuality
    public let direction: EvidenceDirection
    /// Shown word for word. Our own words, about groups of people: no "you",
    /// no digits, no banned, causal or "effect" words.
    public let statement: String
    public let population: String
    /// At least one. Shown in the Sources sheet.
    public let caveats: [String]
    public let strength: EvidenceStrength
    public let sources: [EvidenceSource]
    public let status: EvidenceStatus
    public let surfaces: Set<EvidenceSurface>
    /// Set when the owner signs the card off.
    public let reviewedOn: Day?
    public let reviewers: [String]
    /// Why a card is excluded, held or kept for reference.
    public let note: String?

    public init(
        id: String,
        revision: Int = 1,
        matches: [EvidenceKey],
        matchQuality: MatchQuality = .direct,
        direction: EvidenceDirection,
        statement: String,
        population: String,
        caveats: [String],
        strength: EvidenceStrength,
        sources: [EvidenceSource],
        status: EvidenceStatus = .draft,
        surfaces: Set<EvidenceSurface>,
        reviewedOn: Day? = nil,
        reviewers: [String] = [],
        note: String? = nil
    ) {
        self.id = id
        self.revision = revision
        self.matches = matches
        self.matchQuality = matchQuality
        self.direction = direction
        self.statement = statement
        self.population = population
        self.caveats = caveats
        self.strength = strength
        self.sources = sources
        self.status = status
        self.surfaces = surfaces
        self.reviewedOn = reviewedOn
        self.reviewers = reviewers
        self.note = note
    }

    /// How the person's direction compares with this card. Nil for
    /// background cards.
    public func agreement(with observed: EvidenceDirection) -> EvidenceAgreement? {
        switch direction {
        case .notApplicable: nil
        case .mixed, .noConsistentDifference: .researchMixed
        case .higher, .lower: observed == direction ? .agrees : .differs
        }
    }
}

/// A card shown under one finding. Saved with the summary, so it keeps the
/// card's ID and revision.
public struct ResearchNote: Codable, Sendable, Equatable {
    public let findingID: String
    public let cardID: String
    public let revision: Int
    public let agreement: EvidenceAgreement

    public init(findingID: String, cardID: String, revision: Int, agreement: EvidenceAgreement) {
        self.findingID = findingID
        self.cardID = cardID
        self.revision = revision
        self.agreement = agreement
    }
}

/// The cards a build may show.
public struct EvidenceLibrary: Sendable {
    public let cards: [EvidenceCard]
    public let shownStatuses: Set<EvidenceStatus>

    public init(cards: [EvidenceCard], shownStatuses: Set<EvidenceStatus>) {
        self.cards = cards
        self.shownStatuses = shownStatuses
    }

    /// Release builds: signed-off cards only.
    public static let shipping = EvidenceLibrary(cards: BundledEvidence.cards, shownStatuses: [.ready])
    /// Debug builds: drafts too, labelled as drafts.
    public static let includingDrafts = EvidenceLibrary(cards: BundledEvidence.cards, shownStatuses: [.ready, .draft])
    /// No research notes at all.
    public static let none = EvidenceLibrary(cards: [], shownStatuses: [])

    public func card(id: String) -> EvidenceCard? { cards.first { $0.id == id } }

    func shown(_ card: EvidenceCard, on surface: EvidenceSurface) -> Bool {
        shownStatuses.contains(card.status) && card.surfaces.contains(surface)
    }
}

/// Picks research notes in Swift, never with the model. Pure functions of
/// the findings and the library.
public enum EvidenceMatcher {
    /// At most this many notes per summary, in finding order.
    public static let maximumNotes = 3

    /// Report kinds that show notes. "Why do I feel off today?" never does: a
    /// research line next to "you feel off" would read as a reason.
    public static func showsNotes(in kind: ReportKind) -> Bool {
        switch kind {
        case .daily, .weekly, .monthly: true
        case .feelingOff: false
        }
    }

    /// The notes for a summary: patterns of medium or high confidence whose
    /// direction agrees with the research, or where the research is mixed.
    public static func notes(for findings: [Finding], kind: ReportKind, library: EvidenceLibrary) -> [ResearchNote] {
        guard showsNotes(in: kind) else { return [] }
        var notes: [ResearchNote] = []
        for finding in findings where notes.count < maximumNotes {
            guard let note = match(finding, library: library), note.agreement != .differs else { continue }
            notes.append(note)
        }
        return notes
    }

    /// The card for a finding with its agreement, including when the person's
    /// data differs. For a pattern's own detail screen.
    public static func match(_ finding: Finding, library: EvidenceLibrary) -> ResearchNote? {
        guard (finding.detail.confidence ?? .low) >= .medium,
            let key = EvidenceKey(finding),
            let observed = EvidenceDirection(observedIn: finding)
        else { return nil }
        let candidates = library.cards.filter { library.shown($0, on: .patternNote) && $0.matches.contains(key) }
        guard let card = candidates.min(by: priority), let agreement = card.agreement(with: observed) else {
            return nil
        }
        return ResearchNote(findingID: finding.id, cardID: card.id, revision: card.revision, agreement: agreement)
    }

    /// Background cards for a metric's detail screen.
    public static func context(for metric: Metric, library: EvidenceLibrary) -> [EvidenceCard] {
        library.cards
            .filter { library.shown($0, on: .metricDetail) && $0.matches.contains(.metricContext(metric)) }
            .sorted(by: priority)
    }

    /// Stronger evidence first, then direct matches, then by ID.
    static func priority(_ lhs: EvidenceCard, _ rhs: EvidenceCard) -> Bool {
        if lhs.strength != rhs.strength { return lhs.strength > rhs.strength }
        if lhs.matchQuality != rhs.matchQuality { return lhs.matchQuality == .direct }
        return lhs.id < rhs.id
    }
}

/// Fixed wording around research notes, checked by the same lint as cards.
public enum EvidenceText {
    public static let heading = "Research · groups of people"
    public static let draftLabel = "Draft, not yet reviewed"
    public static let footer =
        "Research notes describe what studies found in groups of people. They can't tell why your data looks the "
        + "way it does."
    public static let differs =
        "Studies of groups of people mostly found the opposite direction. People vary, and findings about groups "
        + "don't apply to everyone."
    public static let withdrawn = "This research note has since been withdrawn."

    public static func strength(_ strength: EvidenceStrength) -> String {
        switch strength {
        case .consistent: "Many studies agree"
        case .moderate: "Some studies"
        case .limited: "A few small studies"
        case .mixed: "Studies disagree"
        }
    }
}
