import Foundation
import FoundationModels
import InsightEngine
import NarrativeCore

/// Drafts summaries with Apple's on-device language model. Its output is
/// always checked by `NarrativeValidator` (through `SummaryComposer`) before
/// anyone sees it.
public struct FoundationModelsNarrator: Narrator {
    public init() {}

    /// True when the device supports Apple Intelligence, it's turned on and
    /// the model is ready.
    public static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    public func draft(findings: [Finding], corrections: [NarrativeViolation]) async throws -> NarrativeDraft {
        // A fresh session per attempt, so a rejected draft doesn't linger in
        // the context; corrections are passed explicitly in the prompt.
        let session = LanguageModelSession(instructions: StyleGuide.modelInstructions)
        let response = try await session.respond(
            to: PromptBuilder.prompt(findings: findings, corrections: corrections),
            generating: GeneratedSummary.self,
            options: GenerationOptions(temperature: 0.2)
        )
        let content = response.content
        return NarrativeDraft(
            headline: content.headline,
            bullets: content.bullets.map { .init(findingID: $0.findingID, text: $0.text) }
        )
    }
}

@Generable
struct GeneratedSummary {
    @Guide(description: "A short, neutral headline for the summary, without numbers")
    var headline: String

    @Guide(description: "One sentence per finding, in the order given")
    var bullets: [GeneratedBullet]
}

@Generable
struct GeneratedBullet {
    @Guide(description: "The id of the finding this sentence restates, copied exactly from the brackets")
    var findingID: String

    @Guide(description: "One sentence restating the finding, using only its numbers")
    var text: String
}
