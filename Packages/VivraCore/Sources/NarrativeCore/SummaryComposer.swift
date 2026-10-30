import Evidence
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
    /// Research notes shown beside the sentences, picked in Swift and never
    /// seen by the model (PLAN decision 11). Empty in summaries saved before
    /// Phase 8.
    public let notes: [ResearchNote]

    public init(draft: NarrativeDraft, generator: NarrativeGenerator, findings: [Finding], notes: [ResearchNote] = []) {
        self.draft = draft
        self.generator = generator
        self.findings = findings
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case draft, generator, findings, notes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generator = try container.decode(NarrativeGenerator.self, forKey: .generator)
        // Model summaries saved before formatting marks were removed.
        let draft = try container.decode(NarrativeDraft.self, forKey: .draft)
        self.draft = generator == .onDeviceModel ? PlainText.clean(draft) : draft
        findings = try container.decode([Finding].self, forKey: .findings)
        notes = try container.decodeIfPresent([ResearchNote].self, forKey: .notes) ?? []
    }

    public func note(for findingID: String) -> ResearchNote? {
        notes.first { $0.findingID == findingID }
    }
}

public enum SummaryComposer {
    /// The on-device model's context is small; send only the top findings.
    /// Report findings are already ordered by priority.
    public static let maximumFindings = 8

    /// Asks the narrator for a draft and validates it. Violations get one
    /// retry with the violations listed; a second failure, a thrown error, or
    /// no narrator falls back to the template renderer.
    /// Research notes come from `evidence`, chosen by `EvidenceMatcher`; the
    /// narrator never sees them.
    public static func compose(
        _ report: InsightReport,
        narrator: (any Narrator)?,
        evidence: EvidenceLibrary = .shipping
    ) async -> ComposedSummary {
        let findings = Array(report.findings.prefix(maximumFindings))
        let notes = EvidenceMatcher.notes(for: findings, kind: report.kind, library: evidence)
        let fallback = ComposedSummary(
            draft: TemplateRenderer.render(findings, kind: report.kind),
            generator: .template,
            findings: findings,
            notes: notes
        )
        guard let narrator, !findings.isEmpty else { return fallback }

        var corrections: [NarrativeViolation] = []
        for attempt in 1...2 {
            do {
                let draft = PlainText.clean(
                    try await narrator.draft(kind: report.kind, findings: findings, corrections: corrections))
                let violations = NarrativeValidator.validate(draft, findings: findings)
                if violations.isEmpty {
                    return ComposedSummary(draft: draft, generator: .onDeviceModel, findings: findings, notes: notes)
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
