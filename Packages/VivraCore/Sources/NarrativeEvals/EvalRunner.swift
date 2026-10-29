import Evidence
import Foundation
import InsightEngine
import NarrativeCore

/// One call to the narrator, as `SummaryComposer` made it.
public struct EvalAttempt: Codable, Sendable, Equatable {
    public let draft: NarrativeDraft?
    /// What `NarrativeValidator` said about the draft.
    public let violations: [String]
    /// The error code, when the call threw.
    public let errorCode: Int?
}

/// One case run once: every attempt, and what the app would have shown.
public struct EvalOutcome: Codable, Sendable, Equatable {
    public let caseID: String
    public let kind: ReportKind
    public let sample: Int
    public let attempts: [EvalAttempt]
    public let shown: NarrativeDraft
    public let generator: NarrativeGenerator
    /// The research notes shown beside it.
    public let notes: [ResearchNote]
    /// Scorer issues for what would have been shown.
    public let issues: [EvalIssue]
    /// Scorer issues for the model's first draft, before any retry.
    public let firstAttemptIssues: [EvalIssue]?

    /// True when the composer asked the narrator at all (it doesn't for an
    /// empty report, or when there's no narrator).
    public var usedNarrator: Bool { !attempts.isEmpty }

    /// The first draft passed the validator, so no retry was needed.
    public var firstAttemptPassedValidator: Bool {
        guard let first = attempts.first else { return false }
        return first.draft != nil && first.violations.isEmpty
    }
}

/// Wraps a narrator and keeps every draft it returns, so the evals can see
/// the attempts that `SummaryComposer` retries or discards.
public actor RecordingNarrator: Narrator {
    private let base: any Narrator
    private var attempts: [EvalAttempt] = []

    public init(_ base: any Narrator) {
        self.base = base
    }

    public func draft(kind: ReportKind, findings: [Finding], corrections: [NarrativeViolation]) async throws
        -> NarrativeDraft
    {
        do {
            let draft = try await base.draft(kind: kind, findings: findings, corrections: corrections)
            let violations = NarrativeValidator.validate(draft, findings: findings).map(\.description)
            attempts.append(EvalAttempt(draft: draft, violations: violations, errorCode: nil))
            return draft
        } catch {
            attempts.append(EvalAttempt(draft: nil, violations: [], errorCode: (error as NSError).code))
            throw error
        }
    }

    /// The attempts since the last call, oldest first.
    public func takeAttempts() -> [EvalAttempt] {
        defer { attempts = [] }
        return attempts
    }
}

public struct EvalThresholds: Codable, Sendable, Equatable {
    /// Share of model calls whose first draft passes the validator.
    public var firstAttemptValidatorPassRate: Double
    /// Share of shown summaries (after retry and fallback) passing every
    /// scorer.
    public var shownPassRate: Double

    public static let standard = EvalThresholds(firstAttemptValidatorPassRate: 0.9, shownPassRate: 1.0)
}

public struct EvalSummary: Codable, Sendable, Equatable {
    public let cases: Int
    public let outcomes: Int
    /// Outcomes where the narrator was asked (reports with findings).
    public let narratorOutcomes: Int
    public let firstAttemptValidatorPassRate: Double
    public let firstAttemptScorerPassRate: Double
    public let shownPassRate: Double
    public let fallbackRate: Double
    public let errorRate: Double
    public let shownIssues: [String: Int]
    public let firstAttemptIssues: [String: Int]
    public let thresholds: EvalThresholds
    /// What missed a threshold. Empty when the run passed.
    public let failures: [String]

    public var passed: Bool { failures.isEmpty }

    public init(outcomes: [EvalOutcome], thresholds: EvalThresholds = .standard) {
        func rate(_ count: Int, of total: Int) -> Double { total == 0 ? 1 : Double(count) / Double(total) }
        func counts(_ issues: [EvalIssue]) -> [String: Int] {
            Dictionary(issues.map { ($0.scorer.rawValue, 1) }, uniquingKeysWith: +)
        }
        let asked = outcomes.filter(\.usedNarrator)
        cases = Set(outcomes.map(\.caseID)).count
        self.outcomes = outcomes.count
        narratorOutcomes = asked.count
        firstAttemptValidatorPassRate = rate(asked.filter(\.firstAttemptPassedValidator).count, of: asked.count)
        firstAttemptScorerPassRate = rate(
            asked.filter { $0.firstAttemptIssues?.isEmpty == true }.count, of: asked.count)
        shownPassRate = rate(outcomes.filter(\.issues.isEmpty).count, of: outcomes.count)
        fallbackRate =
            asked.isEmpty ? 0 : 1 - rate(asked.filter { $0.generator == .onDeviceModel }.count, of: asked.count)
        errorRate =
            asked.isEmpty ? 0 : rate(asked.filter { $0.attempts.first?.errorCode != nil }.count, of: asked.count)
        shownIssues = counts(outcomes.flatMap(\.issues))
        firstAttemptIssues = counts(asked.flatMap { $0.firstAttemptIssues ?? [] })
        self.thresholds = thresholds

        var failures: [String] = []
        if !asked.isEmpty && firstAttemptValidatorPassRate < thresholds.firstAttemptValidatorPassRate {
            failures.append(
                "First-attempt validator pass rate \(percent(firstAttemptValidatorPassRate)) is below "
                    + percent(thresholds.firstAttemptValidatorPassRate) + ".")
        }
        if shownPassRate < thresholds.shownPassRate {
            failures.append(
                "Shown pass rate \(percent(shownPassRate)) is below \(percent(thresholds.shownPassRate)).")
        }
        self.failures = failures
    }
}

func percent(_ value: Double) -> String {
    "\(Int((value * 1000).rounded()) / 10).\(Int((value * 1000).rounded()) % 10)%"
}

public enum EvalRunner {
    /// Runs every case `samples` times through `SummaryComposer`, exactly as
    /// the app does, and scores what it would show. With no narrator, every
    /// summary comes from the templates. Notes come from `evidence`; drafts
    /// are included by default so the note policy is exercised before cards
    /// are signed off.
    public static func run(
        _ cases: [EvalCase],
        narrator: (any Narrator)?,
        samples: Int = 1,
        evidence: EvidenceLibrary = .includingDrafts
    ) async -> [EvalOutcome] {
        let recorder = narrator.map(RecordingNarrator.init)
        var outcomes: [EvalOutcome] = []
        for evalCase in cases {
            for sample in 1...max(1, narrator == nil ? 1 : samples) {
                let composed = await SummaryComposer.compose(evalCase.report, narrator: recorder, evidence: evidence)
                let attempts = await recorder?.takeAttempts() ?? []
                outcomes.append(
                    EvalOutcome(
                        caseID: evalCase.id,
                        kind: evalCase.kind,
                        sample: sample,
                        attempts: attempts,
                        shown: composed.draft,
                        generator: composed.generator,
                        notes: composed.notes,
                        issues: EvalScoring.score(composed.draft, for: evalCase)
                            + EvalScoring.scoreNotes(composed.notes, for: evalCase, library: evidence),
                        firstAttemptIssues: attempts.first?.draft.map { EvalScoring.score($0, for: evalCase) }
                    )
                )
            }
        }
        return outcomes
    }
}
