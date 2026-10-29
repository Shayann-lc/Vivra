import Evidence
import Foundation
import InsightEngine
import NarrativeCore
import Testing

@testable import NarrativeEvals

@Suite struct EvalCorpusTests {
    @Test func coversEveryKindAndFindingTypeWithAtLeastFortyCases() {
        let cases = EvalCorpus.all
        #expect(cases.count >= 40)
        #expect(Set(cases.map(\.id)).count == cases.count)
        #expect(Set(cases.map(\.kind)) == Set(ReportKind.allCases))

        let types = Set(
            cases.flatMap(\.findings).map { finding -> String in
                switch finding.detail {
                case .weeklyAverage: "weeklyAverage"
                case .groupDifference: "groupDifference"
                case .correlation: "correlation"
                case .trend: "trend"
                case .anomaly: "anomaly"
                case .dayComparison: "dayComparison"
                case .periodAverage: "periodAverage"
                case .applicablePattern: "applicablePattern"
                }
            })
        #expect(types.count == 8)

        // The seeded people produce real reports, not just empty ones.
        let seededWithFindings = cases.filter { $0.id.hasPrefix("seed") && !$0.findings.isEmpty }
        #expect(seededWithFindings.count >= 30)
        #expect(cases.contains { $0.findings.isEmpty })
    }

    @Test func isDeterministic() {
        #expect(EvalCorpus.cases() == EvalCorpus.all)
    }
}

@Suite struct TemplateBaselineTests {
    /// The templates are the fallback the app always has, so they must pass
    /// every scorer on every case.
    @Test func templatesPassEveryScorerOnEveryCase() async {
        let cases = EvalCorpus.all
        let outcomes = await EvalRunner.run(cases, narrator: nil)
        let failing = outcomes.filter { !$0.issues.isEmpty }
        #expect(failing.isEmpty, "\(failing.map { "\($0.caseID): \($0.issues)" }.joined(separator: "\n"))")
        let summary = EvalSummary(outcomes: outcomes)
        #expect(summary.shownPassRate == 1)
        #expect(summary.narratorOutcomes == 0)
        #expect(summary.passed)
    }
}

@Suite struct ScorerTests {
    private let evalCase = EvalCorpus.all.first { $0.id == "hand-weekly-full" }!
    private var template: NarrativeDraft { TemplateRenderer.render(evalCase.findings, kind: evalCase.kind) }

    private func replacing(_ id: String, with text: String, in draft: NarrativeDraft) -> NarrativeDraft {
        NarrativeDraft(
            headline: draft.headline,
            bullets: draft.bullets.map { $0.findingID == id ? .init(findingID: id, text: text) : $0 })
    }

    private func scorers(_ draft: NarrativeDraft, _ evalCase: EvalCase? = nil) -> Set<EvalScorer> {
        Set(EvalScoring.score(draft, for: evalCase ?? self.evalCase).map(\.scorer))
    }

    @Test func templateDraftPasses() {
        #expect(EvalScoring.score(template, for: evalCase).isEmpty)
    }

    @Test func validatorCatchesCausalLanguageAndInventedNumbers() {
        let causal = replacing(
            "trend-steps",
            with: "Over the last 90 days, your daily steps went from about 6,200 steps to about 9,800 steps "
                + "because you walked more (84 days recorded, high confidence).",
            in: template)
        #expect(scorers(causal).contains(.validator))
        let invented = NarrativeDraft(headline: "Your week, up 3,141 steps", bullets: template.bullets)
        #expect(scorers(invented).contains(.validator))
    }

    @Test func structureCatchesMissingDuplicatedAndReorderedFindings() {
        let missing = NarrativeDraft(headline: template.headline, bullets: Array(template.bullets.dropLast()))
        #expect(scorers(missing).contains(.structure))
        let duplicated = NarrativeDraft(headline: template.headline, bullets: template.bullets + [template.bullets[0]])
        #expect(scorers(duplicated).contains(.structure))
        let reordered = NarrativeDraft(headline: template.headline, bullets: template.bullets.reversed())
        #expect(scorers(reordered) == [.structure])
    }

    @Test func headlineCatchesDataValues() {
        let draft = NarrativeDraft(headline: "You slept 6h 24m a night", bullets: template.bullets)
        #expect(scorers(draft).contains(.headline))
        let window = NarrativeDraft(headline: "Your last 7 days", bullets: template.bullets)
        #expect(!scorers(window).contains(.headline))
    }

    @Test func keyValuesCatchesAVagueSentence() {
        let vague = replacing("weekly-exercise", with: "Your exercise was up on the week before.", in: template)
        #expect(scorers(vague) == [.keyValues])
    }

    @Test func directionCatchesARiseDescribedAsAFall() {
        let wrong = replacing(
            "trend-steps",
            with: "Over the last 90 days, your daily steps dropped from about 6,200 steps to about 9,800 steps "
                + "(84 days recorded, high confidence).",
            in: template)
        #expect(scorers(wrong) == [.direction])
        let right = replacing(
            "trend-steps",
            with: "Over the last 90 days, your daily steps rose from about 6,200 steps to about 9,800 steps "
                + "(84 days recorded, high confidence).",
            in: template)
        #expect(scorers(right).isEmpty)
    }

    @Test func sentencesCatchesExtraSentences() {
        let wordy = replacing(
            "weekly-exercise",
            with: "Your exercise averaged 48 min over the last 7 days. That is your total. It was 7 days recorded.",
            in: template)
        #expect(scorers(wordy).contains(.sentences))
    }

    @Test func lengthCatchesLongHeadlinesAndRambling() {
        let headline = NarrativeDraft(
            headline: "A calm look back at everything that happened over your last 7 days", bullets: template.bullets)
        #expect(scorers(headline).contains(.length))
        let padded = replacing(
            "weekly-exercise",
            with: "Your exercise averaged 48 min over the last 7 days, compared with 22 min the week before, "
                + "which you can see on your own in the Insights tab whenever you like to look at it again later.",
            in: template)
        #expect(scorers(padded).contains(.length))
    }

    @Test func secondPersonCatchesImpersonalSentences() {
        let impersonal = replacing(
            "weekly-exercise", with: "Exercise averaged 48 min over the last 7 days.", in: template)
        #expect(scorers(impersonal) == [.secondPerson])
    }

    @Test func emptyReportsOnlyNeedAHeadlineAndNoSentences() {
        let empty = EvalCorpus.all.first { $0.id == "hand-daily-empty" }!
        #expect(EvalScoring.score(TemplateRenderer.render([], kind: .daily), for: empty).isEmpty)
        let invented = NarrativeDraft(headline: "Today", bullets: [.init(findingID: "x", text: "You slept well.")])
        #expect(!EvalScoring.score(invented, for: empty).isEmpty)
    }

    @Test func sentenceCountIgnoresDecimalPoints() {
        #expect(EvalScoring.sentenceCount("Your VO2 max was 41.5 mL/kg/min.") == 1)
        #expect(EvalScoring.sentenceCount("Last night you slept 7h. Your median is 7h 6m.") == 2)
    }

    @Test func widgetTextIsTheHeadlineAndFirstTwoSentences() {
        let text = WidgetText.make(from: template)
        #expect(text == ([template.headline] + template.bullets.prefix(2).map(\.text)).joined(separator: "\n"))
    }
}

/// Fake narrators standing in for the on-device model.
private struct TemplateNarrator: Narrator {
    func draft(kind: ReportKind, findings: [Finding], corrections: [NarrativeViolation]) async throws -> NarrativeDraft
    {
        TemplateRenderer.render(findings, kind: kind)
    }
}

private struct CausalNarrator: Narrator {
    func draft(kind: ReportKind, findings: [Finding], corrections: [NarrativeViolation]) async throws -> NarrativeDraft
    {
        let template = TemplateRenderer.render(findings, kind: kind)
        return NarrativeDraft(
            headline: template.headline,
            bullets: template.bullets.map { .init(findingID: $0.findingID, text: $0.text + " This is due to stress.") })
    }
}

/// Bad on the first attempt, fine on the retry.
private actor LearningNarrator: Narrator {
    func draft(kind: ReportKind, findings: [Finding], corrections: [NarrativeViolation]) async throws -> NarrativeDraft
    {
        corrections.isEmpty
            ? try await CausalNarrator().draft(kind: kind, findings: findings, corrections: corrections)
            : TemplateRenderer.render(findings, kind: kind)
    }
}

private struct FailingNarrator: Narrator {
    struct Unavailable: Error {}
    func draft(kind: ReportKind, findings: [Finding], corrections: [NarrativeViolation]) async throws -> NarrativeDraft
    {
        throw Unavailable()
    }
}

@Suite struct EvalRunnerTests {
    private let cases = EvalCorpus.all.filter { $0.id.hasPrefix("hand-") }

    @Test func aModelThatFollowsTheRulesPasses() async {
        let outcomes = await EvalRunner.run(cases, narrator: TemplateNarrator(), samples: 2)
        let summary = EvalSummary(outcomes: outcomes)
        #expect(outcomes.count == cases.count * 2)
        #expect(summary.narratorOutcomes == cases.filter { !$0.findings.isEmpty }.count * 2)
        #expect(summary.firstAttemptValidatorPassRate == 1)
        #expect(summary.firstAttemptScorerPassRate == 1)
        #expect(summary.shownPassRate == 1)
        #expect(summary.fallbackRate == 0)
        #expect(summary.passed)
    }

    @Test func aRetryThatFixesTheDraftIsShownButTheFirstAttemptCounts() async {
        let summary = EvalSummary(outcomes: await EvalRunner.run(cases, narrator: LearningNarrator()))
        #expect(summary.firstAttemptValidatorPassRate == 0)
        #expect(summary.firstAttemptIssues["validator"] ?? 0 > 0)
        #expect(summary.shownPassRate == 1)
        #expect(summary.fallbackRate == 0)
        #expect(!summary.passed)
    }

    @Test func aModelThatKeepsBreakingRulesFallsBackToTemplates() async {
        let outcomes = await EvalRunner.run(cases, narrator: CausalNarrator())
        let summary = EvalSummary(outcomes: outcomes)
        #expect(summary.fallbackRate == 1)
        #expect(summary.shownPassRate == 1)
        #expect(outcomes.filter(\.usedNarrator).allSatisfy { $0.attempts.count == 2 })
        #expect(summary.failures.count == 1)
    }

    @Test func modelErrorsAreCountedAndFallBack() async {
        let summary = EvalSummary(outcomes: await EvalRunner.run(cases, narrator: FailingNarrator()))
        #expect(summary.errorRate == 1)
        #expect(summary.fallbackRate == 1)
        #expect(summary.shownPassRate == 1)
    }

    @Test func reportAndRecordingKeepOnlyGoodModelOutputs() async throws {
        let outcomes = await EvalRunner.run(cases, narrator: LearningNarrator())
        let report = EvalRunReport(runAt: "2026-10-28", environment: "tests", samples: 1, outcomes: outcomes)
        let markdown = report.markdown(cases: cases)
        #expect(markdown.contains("Result: **failed**"))
        #expect(markdown.contains("## Read-through"))
        #expect(!(try report.json()).isEmpty)

        let recorded = RecordedOutputs(from: report, cases: cases)
        #expect(recorded.outputs.count == cases.filter { !$0.findings.isEmpty }.count)
        for output in recorded.outputs {
            #expect(EvalScoring.score(output.draft, for: output.evalCase).isEmpty)
        }
    }
}

@Suite struct RecordedOutputTests {
    /// `evals/recorded/` at the repository root.
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("evals/recorded", isDirectory: true)

    /// Real model outputs saved from live runs must keep passing every
    /// scorer, so changes to the validator, scorers or prompt rules that
    /// would reject them are caught on every push.
    @Test func recordedModelOutputsStillPassEveryScorer() throws {
        let files =
            (try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" } ?? []
        for file in files {
            let recorded = try JSONDecoder().decode(RecordedOutputs.self, from: Data(contentsOf: file))
            for output in recorded.outputs {
                let issues = EvalScoring.score(output.draft, for: output.evalCase)
                #expect(issues.isEmpty, "\(file.lastPathComponent) \(output.caseID): \(issues)")
            }
        }
    }
}

/// Research notes in the evals (PLAN Phase 8).
@Suite struct ResearchNoteEvalTests {
    private func evalCase(_ id: String) throws -> EvalCase {
        try #require(EvalCorpus.all.first { $0.id == id })
    }

    /// Template summaries with draft cards: how many notes each research
    /// case gets, and every note passes the scorer.
    @Test func researchCasesGetTheExpectedNotes() async throws {
        let expected: [String: Int] = [
            "research-agrees": 1, "research-differs": 0, "research-mixed": 2, "research-indirect": 2,
            "research-low-confidence": 0, "research-group": 1, "research-record-only": 0, "research-two-cards": 1,
            "research-cap": 3, "research-feeling-off": 0, "research-anomaly": 0, "research-mixed-with-differs": 1,
        ]
        let cases = EvalCorpus.all.filter { expected[$0.id] != nil }
        #expect(cases.count == expected.count)
        let outcomes = await EvalRunner.run(cases, narrator: nil)
        for outcome in outcomes {
            #expect(outcome.notes.count == expected[outcome.caseID], "\(outcome.caseID)")
            #expect(outcome.issues.isEmpty, "\(outcome.caseID): \(outcome.issues)")
        }
    }

    @Test func releaseLibraryHasNoNotesUntilCardsAreSignedOff() async throws {
        let outcomes = await EvalRunner.run([try evalCase("research-agrees")], narrator: nil, evidence: .shipping)
        #expect(outcomes.first?.notes == [])
        #expect(outcomes.first?.issues == [])
    }

    @Test func researchClaimsCatchesResearchLanguage() throws {
        let evalCase = try evalCase("research-agrees")
        let finding = try #require(evalCase.findings.first)
        let sentence = TemplateRenderer.sentence(for: finding)
        let draft = NarrativeDraft(
            headline: "Your last 7 days",
            bullets: [.init(findingID: finding.id, text: sentence + " Studies have found the same.")])
        let issues = EvalScoring.score(draft, for: evalCase)
        #expect(issues.contains { $0.scorer == .researchClaims })
        #expect(!issues.contains { $0.scorer == .validator })
    }

    @Test func notesScorerCatchesNotesThatBreakThePolicy() throws {
        let library = EvidenceLibrary.includingDrafts
        let agrees = try evalCase("research-agrees")
        let finding = try #require(agrees.findings.first)
        let good = try #require(EvidenceMatcher.match(finding, library: library))
        #expect(EvalScoring.scoreNotes([good], for: agrees, library: library).isEmpty)
        // Missing.
        #expect(EvalScoring.scoreNotes([], for: agrees, library: library).contains { $0.scorer == .notes })
        // The wrong card.
        let wrong = ResearchNote(
            findingID: finding.id, cardID: "caffeine.sleepDuration.nextNight", revision: 1, agreement: .agrees)
        #expect(!EvalScoring.scoreNotes([wrong], for: agrees, library: library).isEmpty)
        // In a report that never shows notes.
        let feelingOff = try evalCase("research-feeling-off")
        #expect(!EvalScoring.scoreNotes([good], for: feelingOff, library: library).isEmpty)
        // Shown although the data differs.
        let differs = try evalCase("research-differs")
        let differingFinding = try #require(differs.findings.first)
        let shown = ResearchNote(
            findingID: differingFinding.id, cardID: good.cardID, revision: good.revision, agreement: .differs)
        #expect(!EvalScoring.scoreNotes([shown], for: differs, library: library).isEmpty)
        // More than three.
        let cap = try evalCase("research-cap")
        let tooMany = cap.findings.compactMap { EvidenceMatcher.match($0, library: library) }
        #expect(tooMany.count > EvidenceMatcher.maximumNotes)
        #expect(!EvalScoring.scoreNotes(tooMany, for: cap, library: library).isEmpty)
    }

    /// Summaries saved before Phase 8 have no notes and must still load.
    @Test func summariesSavedWithoutNotesStillDecode() throws {
        let json = #"{"draft":{"headline":"Your last 7 days","bullets":[]},"generator":"template","findings":[]}"#
        let summary = try JSONDecoder().decode(ComposedSummary.self, from: Data(json.utf8))
        #expect(summary.notes.isEmpty)
        let withNotes = ComposedSummary(
            draft: summary.draft, generator: .template, findings: [],
            notes: [ResearchNote(findingID: "x", cardID: "y", revision: 2, agreement: .researchMixed)])
        let roundTrip = try JSONDecoder().decode(ComposedSummary.self, from: JSONEncoder().encode(withNotes))
        #expect(roundTrip == withNotes)
    }
}
