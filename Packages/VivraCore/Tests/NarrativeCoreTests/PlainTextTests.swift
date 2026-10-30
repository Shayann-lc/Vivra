import Foundation
import InsightEngine
import Testing
import VivraModel

@testable import NarrativeCore

/// The on-device model sometimes writes numbers as maths ("$6h$ $48m$") or
/// adds Markdown; the app shows plain text.
@Suite struct PlainTextTests {
    private static let sleepWeek = Finding(
        id: "weekly.sleepDuration",
        detail: .weeklyAverage(
            WeeklyAverage(
                metric: .sleepDuration, thisWeek: 6 * 3600 + 48 * 60, thisWeekDays: 6, previousWeek: nil,
                previousWeekDays: 2)))

    private struct DollarNarrator: Narrator {
        func draft(kind: ReportKind, findings: [Finding], corrections: [NarrativeViolation]) async throws
            -> NarrativeDraft
        {
            NarrativeDraft(
                headline: "Last **seven** days",
                bullets: [
                    .init(
                        findingID: findings[0].id,
                        text: "You slept an average of $6h$ $48m$ a night over the last $7$ days ($6$ nights recorded)."
                    )
                ])
        }
    }

    @Test func removesDollarSignsAndMarkdown() {
        #expect(
            PlainText.clean("You slept an average of $6h$ $48m$ a night over the last $7$ days ($6$ nights recorded).")
                == "You slept an average of 6h 48m a night over the last 7 days (6 nights recorded).")
        #expect(PlainText.clean("Your **mood** was `4 out of 5`.") == "Your mood was 4 out of 5.")
        #expect(PlainText.clean("Plain text stays as it is.") == "Plain text stays as it is.")
    }

    @Test func modelDraftsAreCleanedBeforeTheyreChecked() async {
        let report = InsightReport(
            kind: .weekly, periodStart: Day(year: 2026, month: 3, day: 25),
            periodEnd: Day(year: 2026, month: 3, day: 31),
            findings: [Self.sleepWeek])
        let summary = await SummaryComposer.compose(report, narrator: DollarNarrator())
        #expect(summary.generator == .onDeviceModel)
        #expect(summary.draft.headline == "Last seven days")
        #expect(summary.draft.bullets.allSatisfy { !$0.text.contains("$") })
    }

    @Test func leftoverMarkupIsRejected() {
        let draft = NarrativeDraft(
            headline: "Your week",
            bullets: [.init(findingID: Self.sleepWeek.id, text: "# You slept an average of 6h 48m a night.")])
        #expect(NarrativeValidator.validate(draft, findings: [Self.sleepWeek]).contains(.markup("#")))
        #expect(StyleGuide.modelInstructions.contains("dollar signs"))
    }

    /// Model summaries saved before this fix are cleaned when they load.
    @Test func savedModelSummariesAreCleanedWhenLoaded() throws {
        let json = #"""
            {"draft":{"headline":"Last seven days","bullets":[{"findingID":"a","text":"Over $7$ days."}]},
            "generator":"onDeviceModel","findings":[]}
            """#
        let summary = try JSONDecoder().decode(ComposedSummary.self, from: Data(json.utf8))
        #expect(summary.draft.bullets.first?.text == "Over 7 days.")
    }
}
