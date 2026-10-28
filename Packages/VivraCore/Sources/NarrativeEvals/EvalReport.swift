import Foundation
import InsightEngine
import NarrativeCore

/// Everything a run produced, saved as JSON next to the Markdown report.
public struct EvalRunReport: Codable, Sendable {
    /// When and on what the run happened, as given by the runner.
    public let runAt: String
    public let environment: String
    public let samples: Int
    public let summary: EvalSummary
    public let outcomes: [EvalOutcome]

    public init(
        runAt: String, environment: String, samples: Int, outcomes: [EvalOutcome],
        thresholds: EvalThresholds = .standard
    ) {
        self.runAt = runAt
        self.environment = environment
        self.samples = samples
        self.summary = EvalSummary(outcomes: outcomes, thresholds: thresholds)
        self.outcomes = outcomes
    }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// For people: rates, failures, and each case's model sentences next to
    /// the template's, to read through.
    public func markdown(cases: [EvalCase]) -> String {
        let summary = summary
        var lines = [
            "# Vivra narrative evals",
            "",
            "- Run: \(runAt)",
            "- Environment: \(environment)",
            "- Cases: \(summary.cases), samples per case: \(samples), outcomes: \(summary.outcomes) "
                + "(\(summary.narratorOutcomes) asked the model)",
            "- Result: **\(summary.passed ? "passed" : "failed")**",
            "",
            "| Measure | Value | Threshold |",
            "|---|---|---|",
            "| First draft passes the validator | \(percent(summary.firstAttemptValidatorPassRate)) | "
                + "≥ \(percent(summary.thresholds.firstAttemptValidatorPassRate)) |",
            "| First draft passes every scorer | \(percent(summary.firstAttemptScorerPassRate)) | – |",
            "| Shown summary passes every scorer | \(percent(summary.shownPassRate)) | "
                + "≥ \(percent(summary.thresholds.shownPassRate)) |",
            "| Fell back to the template | \(percent(summary.fallbackRate)) | – |",
            "| Model call failed | \(percent(summary.errorRate)) | – |",
            "",
        ]
        if !summary.failures.isEmpty {
            lines += ["## Thresholds missed", ""] + summary.failures.map { "- \($0)" } + [""]
        }
        lines += ["## Issues by scorer", "", "| Scorer | First drafts | Shown |", "|---|---|---|"]
        for scorer in EvalScorer.allCases {
            let first = summary.firstAttemptIssues[scorer.rawValue] ?? 0
            let shown = summary.shownIssues[scorer.rawValue] ?? 0
            lines.append("| \(scorer.rawValue) | \(first) | \(shown) |")
        }
        lines.append("")

        let flagged = outcomes.filter { !$0.issues.isEmpty || $0.firstAttemptIssues?.isEmpty == false }
        if !flagged.isEmpty {
            lines += ["## Outcomes with issues", ""]
            for outcome in flagged {
                lines.append("### \(outcome.caseID), sample \(outcome.sample) (\(outcome.generator.rawValue))")
                if let first = outcome.firstAttemptIssues, !first.isEmpty {
                    lines.append("First draft:")
                    lines += first.map { "- \($0)" }
                }
                if !outcome.issues.isEmpty {
                    lines.append("Shown:")
                    lines += outcome.issues.map { "- \($0)" }
                }
                lines.append("")
            }
        }

        lines += ["## Read-through (first sample of each case)", ""]
        let byCase = Dictionary(grouping: outcomes, by: \.caseID)
        for evalCase in cases {
            guard let outcome = byCase[evalCase.id]?.min(by: { $0.sample < $1.sample }) else { continue }
            lines.append("### \(evalCase.id) — \(evalCase.kind.rawValue)")
            lines.append("**\(outcome.shown.headline)** (\(outcome.generator.rawValue))")
            let shownByID = Dictionary(
                outcome.shown.bullets.map { ($0.findingID, $0.text) }, uniquingKeysWith: { first, _ in first })
            for finding in evalCase.findings {
                lines.append("- Template: \(TemplateRenderer.sentence(for: finding))")
                lines.append("  - Shown: \(shownByID[finding.id] ?? "(missing)")")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

/// Model outputs saved from a live run and re-scored in CI on every push,
/// with the findings they were written from, so a change to the prompt,
/// validator or scorers that would reject them fails the build.
public struct RecordedOutputs: Codable, Sendable {
    public struct Output: Codable, Sendable {
        public let caseID: String
        public let kind: ReportKind
        public let findings: [Finding]
        public let draft: NarrativeDraft

        public init(caseID: String, kind: ReportKind, findings: [Finding], draft: NarrativeDraft) {
            self.caseID = caseID
            self.kind = kind
            self.findings = findings
            self.draft = draft
        }

        public var evalCase: EvalCase { EvalCase(id: caseID, kind: kind, findings: findings) }
    }

    public let recordedAt: String
    public let environment: String
    public let outputs: [Output]

    public init(recordedAt: String, environment: String, outputs: [Output]) {
        self.recordedAt = recordedAt
        self.environment = environment
        self.outputs = outputs
    }

    /// The model-written summaries from a run that would be shown and pass
    /// every scorer, one per case.
    public init(from report: EvalRunReport, cases: [EvalCase]) {
        let byID = Dictionary(cases.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<String> = []
        var outputs: [Output] = []
        for outcome in report.outcomes
        where outcome.generator == .onDeviceModel && outcome.issues.isEmpty && !seen.contains(outcome.caseID) {
            guard let evalCase = byID[outcome.caseID] else { continue }
            seen.insert(outcome.caseID)
            outputs.append(
                Output(caseID: outcome.caseID, kind: outcome.kind, findings: evalCase.findings, draft: outcome.shown))
        }
        self.init(recordedAt: report.runAt, environment: report.environment, outputs: outputs)
    }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
