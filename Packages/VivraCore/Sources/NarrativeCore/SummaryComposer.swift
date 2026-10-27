import Foundation
import InsightEngine
import VivraLogging

/// Something that drafts a narrative from findings, such as the on-device
/// Foundation Models narrator.
public protocol Narrator: Sendable {
    func draft(kind: ReportKind, findings: [Finding], corrections: [NarrativeViolation]) async throws
        -> NarrativeDraft
}

public enum NarrativeGenerator: String, Codable, Sendable {
    case onDeviceModel
    case template
}

public struct ComposedSummary: Codable, Sendable, Equatable {
    public let draft: NarrativeDraft
    public let generator: NarrativeGenerator
    /// The findings the summary was written from (at most
    /// `SummaryComposer.maximumFindings`).
    public let findings: [Finding]
}

public enum SummaryComposer {
    /// The on-device model's context is small; send only the top findings.
    /// Report findings are already ordered by priority.
    public static let maximumFindings = 8

    /// Asks the narrator for a draft and validates it. Violations get one
    /// retry with the violations listed; a second failure, a thrown error, or
    /// no narrator falls back to the template renderer.
    public static func compose(_ report: InsightReport, narrator: (any Narrator)?) async -> ComposedSummary {
        let findings = Array(report.findings.prefix(maximumFindings))
        let fallback = ComposedSummary(
            draft: TemplateRenderer.render(findings, kind: report.kind),
            generator: .template,
            findings: findings
        )
        guard let narrator, !findings.isEmpty else { return fallback }

        var corrections: [NarrativeViolation] = []
        for attempt in 1...2 {
            do {
                let draft = try await narrator.draft(kind: report.kind, findings: findings, corrections: corrections)
                let violations = NarrativeValidator.validate(draft, findings: findings)
                if violations.isEmpty {
                    return ComposedSummary(draft: draft, generator: .onDeviceModel, findings: findings)
                }
                Log.narrative.event("Model draft rejected, violations", count: violations.count)
                corrections = violations
            } catch {
                Log.narrative.failure("Model draft failed", code: (error as NSError).code)
                break
            }
            if attempt == 2 { Log.narrative.event("Falling back to template") }
        }
        return fallback
    }
}

/// Builds the user prompt for a narrator.
public enum PromptBuilder {
    public static func prompt(kind: ReportKind, findings: [Finding], corrections: [NarrativeViolation]) -> String {
        let task =
            switch kind {
            case .weekly: "Write a summary of the person's last 7 days from these findings."
            case .daily: "Write a short check-in for the person's day from these findings."
            case .monthly: "Write a summary of the person's last 30 days from these findings."
            case .feelingOff:
                "The person asked why they might feel off today. Restate these findings as things that stood out "
                    + "or patterns seen before. Never say or suggest that any of them is the reason."
            }
        var lines = [
            task,
            "Write one sentence per finding, and set findingID to the id shown in brackets.",
            "Write a short headline without numbers.",
            "",
            "Findings:",
        ]
        for finding in findings {
            lines.append("[\(finding.id)] \(TemplateRenderer.sentence(for: finding))")
        }
        if !corrections.isEmpty {
            lines.append("")
            lines.append("Your previous answer broke these rules. Write it again without these problems:")
            lines += corrections.map { "- \($0.description)" }
        }
        return lines.joined(separator: "\n")
    }
}
