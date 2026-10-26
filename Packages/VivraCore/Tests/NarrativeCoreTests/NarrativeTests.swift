import Foundation
import InsightEngine
import Testing
import VivraModel

@testable import NarrativeCore

private let sleepWeek = Finding(
    id: "weekly.sleepDuration",
    detail: .weeklyAverage(
        WeeklyAverage(
            metric: .sleepDuration, thisWeek: 7 * 3600 + 5 * 60, thisWeekDays: 6, previousWeek: 6.5 * 3600,
            previousWeekDays: 7)
    )
)
private let restingWeek = Finding(
    id: "weekly.restingHeartRate",
    detail: .weeklyAverage(
        WeeklyAverage(
            metric: .restingHeartRate, thisWeek: 58.4, thisWeekDays: 7, previousWeek: 60.6, previousWeekDays: 7)
    )
)
private let vo2Week = Finding(
    id: "weekly.vo2Max",
    detail: .weeklyAverage(
        WeeklyAverage(metric: .vo2Max, thisWeek: 41.26, thisWeekDays: 3, previousWeek: nil, previousWeekDays: 1))
)
private let workoutWeek = Finding(
    id: "weekly.workoutCount",
    detail: .weeklyAverage(
        WeeklyAverage(metric: .workoutCount, thisWeek: 1, thisWeekDays: 7, previousWeek: 3, previousWeekDays: 7))
)
private let sleepPattern = Finding(
    id: "pattern.shorterSleep.restingHeartRate",
    detail: .groupDifference(
        GroupDifference(
            condition: .shorterSleep,
            conditionThreshold: 6.75 * 3600,
            outcome: .restingHeartRate,
            withConditionMedian: 63,
            withoutConditionMedian: 59,
            withConditionDays: 24,
            withoutConditionDays: 26,
            differenceLow: 2,
            differenceHigh: 6,
            pValue: 0.001,
            adjustedPValue: 0.002,
            confidence: .high
        )
    )
)
private let workoutPattern = Finding(
    id: "pattern.workoutDay.sleepDuration",
    detail: .groupDifference(
        GroupDifference(
            condition: .workoutDay,
            conditionThreshold: 20,
            outcome: .sleepDuration,
            withConditionMedian: 7.5 * 3600,
            withoutConditionMedian: 7 * 3600,
            withConditionDays: 9,
            withoutConditionDays: 30,
            differenceLow: 900,
            differenceHigh: 2700,
            pValue: 0.03,
            adjustedPValue: 0.06,
            confidence: .low
        )
    )
)
private let allFindings = [sleepPattern, workoutPattern, sleepWeek, restingWeek, vo2Week, workoutWeek]

@Suite struct FormatterTests {
    @Test func formatsEachUnit() {
        #expect(FindingFormatter.format(7 * 3600 + 5 * 60 + 29, .seconds) == "7h 5m")
        #expect(FindingFormatter.format(45 * 60, .seconds) == "45m")
        #expect(FindingFormatter.format(58.5, .beatsPerMinute) == "59 bpm")
        #expect(FindingFormatter.format(41.26, .millilitersPerKilogramMinute) == "41.3 mL/kg/min")
        #expect(FindingFormatter.format(95.2, .minutes) == "95 min")
    }

    @Test func extractsAndNormalizesNumbers() {
        #expect(NumberTokens.extract(from: "Slept 7h 05m, then 41.30 and 1,200.") == ["7", "5", "41.3", "1200"])
        #expect(NumberTokens.extract(from: "Your VO2 max was 41.3.") == ["41.3"])
        #expect(NumberTokens.extract(from: "No numbers here") == [])
    }
}

@Suite struct ValidatorTests {
    @Test func templateOutputAlwaysPasses() {
        let draft = TemplateRenderer.render(allFindings)
        #expect(NarrativeValidator.validate(draft, findings: allFindings).isEmpty)
        #expect(draft.bullets.count == allFindings.count)
    }

    @Test func templateIsDeterministicGolden() {
        #expect(
            TemplateRenderer.sentence(for: sleepPattern)
                == "On days after a night shorter than your median of 6h 45m, your resting heart rate had a median "
                + "of 63 bpm, compared with 59 bpm after longer nights (24 and 26 days compared, high confidence)."
        )
        #expect(
            TemplateRenderer.sentence(for: sleepWeek)
                == "You slept an average of 7h 5m a night over the last 7 days (6 nights recorded). "
                + "The week before, the average was 6h 30m."
        )
        #expect(
            TemplateRenderer.sentence(for: workoutWeek)
                == "You recorded 1 workout over the last 7 days, compared with 3 the week before.")
    }

    @Test func acceptsAFaithfulRewording() {
        let draft = NarrativeDraft(
            headline: "A steady week",
            bullets: [
                .init(
                    findingID: "weekly.restingHeartRate",
                    text: "Your resting heart rate averaged 58 bpm, 2 bpm lower than the 61 bpm the week before."),
                .init(
                    findingID: "pattern.shorterSleep.restingHeartRate",
                    text:
                        "After nights under 6h 45m, your resting heart rate was 4 bpm higher: 63 bpm compared with 59 bpm."
                ),
            ]
        )
        #expect(NarrativeValidator.validate(draft, findings: allFindings) == [])
    }

    @Test func rejectsInventedNumbers() {
        let draft = NarrativeDraft(
            headline: "Your week",
            bullets: [.init(findingID: "weekly.restingHeartRate", text: "Your resting heart rate averaged 55 bpm.")]
        )
        #expect(
            NarrativeValidator.validate(draft, findings: allFindings) == [
                .unsupportedNumber("55", findingID: "weekly.restingHeartRate")
            ])
    }

    @Test func rejectsNumbersBorrowedFromAnotherFinding() {
        let draft = NarrativeDraft(
            headline: "Your week",
            bullets: [.init(findingID: "weekly.restingHeartRate", text: "Your resting heart rate averaged 63 bpm.")]
        )
        #expect(
            NarrativeValidator.validate(draft, findings: allFindings).contains(
                .unsupportedNumber("63", findingID: "weekly.restingHeartRate")))
    }

    @Test func rejectsUnknownFindingsAndEmptyDrafts() {
        let unknown = NarrativeDraft(headline: "Hi", bullets: [.init(findingID: "made.up", text: "Something.")])
        #expect(NarrativeValidator.validate(unknown, findings: allFindings) == [.unknownFinding("made.up")])
        #expect(
            NarrativeValidator.validate(NarrativeDraft(headline: "", bullets: []), findings: allFindings) == [.empty])
    }

    @Test func rejectsJudgementAndCausalLanguage() {
        let draft = NarrativeDraft(
            headline: "A bad week",
            bullets: [
                .init(
                    findingID: "pattern.shorterSleep.restingHeartRate",
                    text: "Short sleep causes a higher resting heart rate, so you should sleep more.")
            ]
        )
        let violations = NarrativeValidator.validate(draft, findings: allFindings)
        #expect(violations.contains(.bannedTerm("bad")))
        #expect(violations.contains(.bannedTerm("should")))
        #expect(violations.contains(.causalLanguage("causes")))
    }

    @Test func matchesWholeWordsOnly() {
        #expect(NarrativeValidator.containsPhrase("bad", in: "A badminton session") == false)
        #expect(NarrativeValidator.containsPhrase("treat", in: "a treatment plan") == false)
        #expect(NarrativeValidator.containsPhrase("due to", in: "This was Due to rain") == true)
        #expect(NarrativeValidator.containsPhrase("cause", in: "because") == false)
    }

    @Test func headlineNumbersMustComeFromSomeFinding() {
        let draft = NarrativeDraft(
            headline: "99 reasons",
            bullets: [.init(findingID: "weekly.vo2Max", text: "Your VO2 max estimate averaged 41.3 mL/kg/min.")])
        #expect(NarrativeValidator.validate(draft, findings: allFindings) == [.unsupportedNumber("99", findingID: nil)])
    }
}

private actor ScriptedNarrator: Narrator {
    private var responses: [Result<NarrativeDraft, any Error>]
    private(set) var receivedCorrections: [[NarrativeViolation]] = []

    init(_ responses: [Result<NarrativeDraft, any Error>]) {
        self.responses = responses
    }

    func draft(findings: [Finding], corrections: [NarrativeViolation]) async throws -> NarrativeDraft {
        receivedCorrections.append(corrections)
        return try responses.removeFirst().get()
    }
}

@Suite struct ComposerTests {
    private let report = WeeklyReport(
        periodStart: .init(year: 2026, month: 3, day: 25),
        periodEnd: .init(year: 2026, month: 3, day: 31),
        findings: allFindings
    )
    private let good = NarrativeDraft(
        headline: "Your week",
        bullets: [.init(findingID: "weekly.restingHeartRate", text: "Your resting heart rate averaged 58 bpm.")]
    )
    private let bad = NarrativeDraft(
        headline: "Your week",
        bullets: [.init(findingID: "weekly.restingHeartRate", text: "Your resting heart rate averaged 50 bpm.")]
    )

    @Test func usesValidModelOutput() async {
        let summary = await SummaryComposer.compose(report, narrator: ScriptedNarrator([.success(good)]))
        #expect(summary.generator == .onDeviceModel)
        #expect(summary.draft == good)
    }

    @Test func retriesOnceWithCorrections() async {
        let narrator = ScriptedNarrator([.success(bad), .success(good)])
        let summary = await SummaryComposer.compose(report, narrator: narrator)
        #expect(summary.generator == .onDeviceModel)
        let corrections = await narrator.receivedCorrections
        #expect(corrections.count == 2)
        #expect(corrections[1] == [.unsupportedNumber("50", findingID: "weekly.restingHeartRate")])
    }

    @Test func fallsBackAfterTwoRejectedDrafts() async {
        let summary = await SummaryComposer.compose(report, narrator: ScriptedNarrator([.success(bad), .success(bad)]))
        #expect(summary.generator == .template)
        #expect(summary.draft == TemplateRenderer.render(allFindings))
    }

    @Test func fallsBackWhenTheModelThrows() async {
        let summary = await SummaryComposer.compose(
            report, narrator: ScriptedNarrator([.failure(NSError(domain: "x", code: 1))]))
        #expect(summary.generator == .template)
    }

    @Test func usesTemplateWithoutANarrator() async {
        #expect(await SummaryComposer.compose(report, narrator: nil).generator == .template)
    }

    @Test func capsFindingsSentToTheModel() async {
        let many = WeeklyReport(
            periodStart: report.periodStart, periodEnd: report.periodEnd, findings: allFindings + allFindings)
        let summary = await SummaryComposer.compose(many, narrator: nil)
        #expect(summary.findings.count == SummaryComposer.maximumFindings)
    }

    @Test func promptListsFindingIDsAndCorrections() {
        let prompt = PromptBuilder.prompt(findings: [restingWeek], corrections: [.bannedTerm("bad")])
        #expect(prompt.contains("[weekly.restingHeartRate] Your resting heart rate averaged 58 bpm"))
        #expect(prompt.contains("The word \"bad\" is not allowed."))
    }
}
