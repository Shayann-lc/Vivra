import Foundation
import InsightEngine
import NarrativeCore
import Testing
import VivraModel

@testable import Evidence

/// Hand-made findings, so each matcher rule is tested on its own.
enum Make {
    static func correlation(
        _ x: Metric, _ y: Metric, lag: Int, low: Double, high: Double, confidence: Confidence = .medium
    ) -> Finding {
        Finding(
            id: "pattern.\(x.rawValue).\(y.rawValue).lag\(lag)",
            detail: .correlation(
                Correlation(
                    x: x, y: y, lag: lag, rho: high > low ? 0.4 : -0.4, rhoLow: 0.2, rhoHigh: 0.6, days: 60,
                    pValue: 0.001, adjustedPValue: 0.01, confidence: confidence, split: .thirds, lowGroupMaxX: 1,
                    highGroupMinX: 2, lowGroupMedianY: low, highGroupMedianY: high, lowGroupDays: 20,
                    highGroupDays: 20)))
    }

    static func group(_ condition: Condition, _ outcome: Metric, with: Double, without: Double) -> Finding {
        Finding(
            id: "pattern.\(condition.rawValue).\(outcome.rawValue)",
            detail: .groupDifference(
                GroupDifference(
                    condition: condition, conditionThreshold: 20, outcome: outcome, withConditionMedian: with,
                    withoutConditionMedian: without, withConditionDays: 30, withoutConditionDays: 30,
                    differenceLow: 1, differenceHigh: 2, pValue: 0.001, adjustedPValue: 0.01, confidence: .high)))
    }

    static let alcoholLowersHRV = correlation(.alcohol, .heartRateVariability, lag: 1, low: 50, high: 42)
}

@Suite struct EvidenceMatcherTests {
    let drafts = EvidenceLibrary.includingDrafts

    @Test func matchesAPatternThatAgrees() throws {
        let note = try #require(EvidenceMatcher.match(Make.alcoholLowersHRV, library: drafts))
        #expect(note.cardID == "alcohol.hrv.nextNight")
        #expect(note.agreement == .agrees)
        #expect(note.findingID == Make.alcoholLowersHRV.id)
        #expect(note.revision == drafts.card(id: note.cardID)?.revision)
    }

    @Test func releaseBuildsShowOnlySignedOffCards() {
        #expect(EvidenceMatcher.match(Make.alcoholLowersHRV, library: .shipping) == nil)
        let signedOff = BundledEvidence.cards.map { card in
            card.id == "alcohol.hrv.nextNight" ? Self.signOff(card) : card
        }
        let release = EvidenceLibrary(cards: signedOff, shownStatuses: [.ready])
        #expect(EvidenceMatcher.match(Make.alcoholLowersHRV, library: release)?.cardID == "alcohol.hrv.nextNight")
        #expect(EvidenceMatcher.match(Make.alcoholLowersHRV, library: .none) == nil)
    }

    @Test func differingDataGetsNoNoteInASummary() throws {
        let rising = Make.correlation(.alcohol, .heartRateVariability, lag: 1, low: 42, high: 50)
        #expect(EvidenceMatcher.match(rising, library: drafts)?.agreement == .differs)
        #expect(EvidenceMatcher.notes(for: [rising], kind: .weekly, library: drafts).isEmpty)
    }

    @Test func mixedResearchIsShownEitherWay() {
        let hour: Double = 3600
        let pairs: [(low: Double, high: Double)] = [(7 * hour, 6.5 * hour), (6.5 * hour, 7 * hour)]
        for pair in pairs {
            let finding = Make.correlation(.alcohol, .sleepDuration, lag: 1, low: pair.low, high: pair.high)
            let notes: [ResearchNote] = EvidenceMatcher.notes(for: [finding], kind: .weekly, library: drafts)
            let agreements: [EvidenceAgreement] = notes.map { $0.agreement }
            #expect(agreements == [EvidenceAgreement.researchMixed])
        }
    }

    @Test func lowConfidencePatternsGetNoNote() {
        let low = Make.correlation(.alcohol, .heartRateVariability, lag: 1, low: 50, high: 42, confidence: .low)
        #expect(EvidenceMatcher.match(low, library: drafts) == nil)
    }

    @Test func onlyDailyWeeklyAndMonthlySummariesShowNotes() {
        for kind in ReportKind.allCases {
            let notes = EvidenceMatcher.notes(for: [Make.alcoholLowersHRV], kind: kind, library: drafts)
            #expect(notes.isEmpty == (kind == .feelingOff), "\(kind)")
        }
    }

    @Test func groupDifferencesMatchByCondition() throws {
        let workouts = Make.group(.workoutDay, .sleepDuration, with: 7.4 * 3600, without: 7 * 3600)
        #expect(try #require(EvidenceMatcher.match(workouts, library: drafts)).agreement == .agrees)
        // The shorter-sleep card compares people, not nights, so it's kept for
        // the record and never shown.
        let shorter = Make.group(.shorterSleep, .restingHeartRate, with: 59, without: 57)
        #expect(EvidenceMatcher.match(shorter, library: drafts) == nil)
    }

    @Test func descriptiveFindingsGetNoNote() {
        let anomaly = Finding(
            id: "anomaly.restingHeartRate",
            detail: .anomaly(
                Anomaly(metric: .restingHeartRate, daysAgo: 0, value: 70, usualLow: 55, usualHigh: 60, baselineDays: 28)
            ))
        #expect(EvidenceMatcher.notes(for: [anomaly], kind: .daily, library: drafts).isEmpty)
    }

    @Test func atMostThreeNotesInFindingOrder() {
        let findings = [
            Make.correlation(.caffeine, .sleepDuration, lag: 1, low: 7.4 * 3600, high: 6.8 * 3600),
            Make.alcoholLowersHRV,
            Make.correlation(.sleepDuration, .mood, lag: 0, low: 3, high: 4),
            Make.correlation(.steps, .mood, lag: 0, low: 3, high: 4),
            Make.correlation(.mindfulMinutes, .sleepDuration, lag: 1, low: 7 * 3600, high: 7.4 * 3600),
        ]
        let notes = EvidenceMatcher.notes(for: findings, kind: .monthly, library: drafts)
        #expect(notes.count == EvidenceMatcher.maximumNotes)
        #expect(notes.map(\.findingID) == findings.prefix(3).map(\.id))
    }

    @Test func strongerEvidenceWinsWhenTwoCardsMatch() {
        let sleepMood = Make.correlation(.sleepDuration, .mood, lag: 0, low: 3, high: 4)
        #expect(EvidenceMatcher.match(sleepMood, library: drafts)?.cardID == "sleep.mood.experiments")
    }

    @Test func metricDetailShowsBackgroundCards() {
        let hrv = EvidenceMatcher.context(for: .heartRateVariability, library: drafts).map(\.id)
        #expect(hrv == ["hrv.measurement", "hrv.dayToDay"])
        #expect(EvidenceMatcher.context(for: .heartRateVariability, library: .shipping).isEmpty)
        #expect(EvidenceMatcher.context(for: .weight, library: drafts).isEmpty)
    }

    @Test func agreementFollowsTheCardsDirection() throws {
        let lower = try #require(BundledEvidence.cards.first { $0.direction == .lower })
        #expect(lower.agreement(with: .lower) == .agrees)
        #expect(lower.agreement(with: .higher) == .differs)
        let mixed = try #require(BundledEvidence.cards.first { $0.direction == .mixed })
        #expect(mixed.agreement(with: .higher) == .researchMixed)
        let background = try #require(BundledEvidence.cards.first { $0.direction == .notApplicable })
        #expect(background.agreement(with: .higher) == nil)
    }

    @Test func notesRoundTripThroughJSON() throws {
        let note = try #require(EvidenceMatcher.match(Make.alcoholLowersHRV, library: drafts))
        let decoded = try JSONDecoder().decode(ResearchNote.self, from: JSONEncoder().encode(note))
        #expect(decoded == note)
    }

    static func signOff(_ card: EvidenceCard) -> EvidenceCard {
        EvidenceCard(
            id: card.id, revision: card.revision, matches: card.matches, matchQuality: card.matchQuality,
            direction: card.direction, statement: card.statement, population: card.population,
            caveats: card.caveats, strength: card.strength, sources: card.sources, status: .ready,
            surfaces: card.surfaces, reviewedOn: Day(year: 2026, month: 11, day: 1), reviewers: ["Owner"])
    }
}

/// The rules every card follows (docs/EVIDENCE.md, STYLE_GUIDE.md).
@Suite struct EvidenceCardLintTests {
    static let shownCards = BundledEvidence.cards.filter { $0.status == .ready || $0.status == .draft }

    private static func phrases(in text: String) -> [String] {
        (StyleGuide.bannedTerms + StyleGuide.causalPhrases + StyleGuide.researchNoteAvoids)
            .filter { NarrativeValidator.containsPhrase($0, in: text) }
    }

    @Test func idsAreUnique() {
        let ids = BundledEvidence.cards.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func enoughCardsAreDraftedOrReady() {
        #expect(Self.shownCards.count >= 20)
    }

    @Test func statementsFollowTheStyleGuide() {
        for card in Self.shownCards {
            let text = card.statement
            #expect(Self.phrases(in: text).isEmpty, "\(card.id): \(Self.phrases(in: text))")
            let hasDigit = text.contains { $0.isNumber }
            #expect(!hasDigit, "\(card.id) has a digit")
            for word in ["you", "your", "you're", "yours"] {
                #expect(!NarrativeValidator.containsPhrase(word, in: text), "\(card.id) says \(word)")
            }
            let words = text.split(whereSeparator: \.isWhitespace).count
            #expect(words <= 45, "\(card.id) has \(words) words")
            #expect(
                ["In ", "Across ", "Research on "].contains { text.hasPrefix($0) },
                "\(card.id) should start by naming the evidence")
        }
    }

    @Test func caveatsAndPopulationsFollowTheStyleGuide() {
        for card in Self.shownCards {
            #expect(!card.caveats.isEmpty, "\(card.id) needs a caveat")
            #expect(!card.population.isEmpty, "\(card.id) needs a population")
            for text in card.caveats + [card.population] {
                #expect(Self.phrases(in: text).isEmpty, "\(card.id): \(Self.phrases(in: text))")
                #expect(!NarrativeValidator.containsPhrase("you", in: text), "\(card.id): \(text)")
            }
        }
    }

    @Test func everySourceIsCitedWithItsLicence() {
        for card in Self.shownCards {
            #expect(!card.sources.isEmpty, "\(card.id) needs a source")
            for source in card.sources {
                #expect(source.url.hasPrefix("https://"), "\(card.id)")
                #expect(source.doi.map { source.url == "https://doi.org/\($0)" } ?? true, "\(card.id)")
                #expect(!source.licence.isEmpty && !source.design.isEmpty, "\(card.id)")
                #expect(source.year >= 1990, "\(card.id)")
            }
        }
    }

    @Test func indirectMatchesSayWhatWasMeasured() {
        for card in Self.shownCards where card.matchQuality == .indirect {
            #expect(card.statement.contains("measured"), "\(card.id)")
        }
    }

    @Test func surfacesFitTheKeys() {
        for card in Self.shownCards {
            #expect(!card.surfaces.isEmpty, "\(card.id)")
            for key in card.matches {
                switch key {
                case .metricContext:
                    #expect(card.surfaces == [.metricDetail], "\(card.id)")
                    #expect(card.direction == .notApplicable, "\(card.id)")
                case .correlation, .groupDifference:
                    #expect(card.surfaces == [.patternNote], "\(card.id)")
                    #expect(card.direction != .notApplicable, "\(card.id)")
                }
            }
        }
    }

    @Test func signedOffCardsNameTheirReviewers() {
        for card in BundledEvidence.cards where card.status == .ready {
            #expect(card.reviewedOn != nil && !card.reviewers.isEmpty, "\(card.id)")
        }
    }

    @Test func recordOnlyCardsSayWhyAndAreNeverShown() {
        for card in BundledEvidence.cards where card.status == .excluded || card.status == .referenceOnly {
            #expect(!(card.note ?? "").isEmpty, "\(card.id)")
            #expect(card.surfaces.isEmpty, "\(card.id)")
        }
    }

    /// Every check the engine makes has a card, shown or kept for the record,
    /// so the reason it's tested is written down.
    @Test func everyPatternCheckHasACard() {
        let keys = Set(BundledEvidence.cards.flatMap(\.matches))
        for pair in PatternCatalog.correlations {
            #expect(keys.contains(.correlation(x: pair.x, y: pair.y, lag: pair.lag)), "\(pair.id)")
        }
        #expect(keys.contains(.groupDifference(.shorterSleep, outcome: .restingHeartRate)))
        #expect(keys.contains(.groupDifference(.workoutDay, outcome: .sleepDuration)))
    }

    @Test func fixedTextFollowsTheStyleGuide() {
        let texts =
            [
                EvidenceText.heading, EvidenceText.draftLabel, EvidenceText.footer, EvidenceText.differs,
                EvidenceText.withdrawn,
            ]
            + [EvidenceStrength.consistent, .moderate, .limited, .mixed].map(EvidenceText.strength)
        for text in texts {
            #expect(Self.phrases(in: text).isEmpty, "\(text): \(Self.phrases(in: text))")
        }
    }

    @Test func modelInstructionsForbidResearch() {
        #expect(StyleGuide.modelInstructions.contains("Don't mention research"))
        let draft = NarrativeDraft(
            headline: "Your week",
            bullets: [.init(findingID: "x", text: "Studies show this is common.")])
        let violations = NarrativeValidator.validate(
            draft, findings: [Finding(id: "x", detail: Make.alcoholLowersHRV.detail)])
        #expect(violations.contains(.researchClaim("studies")))
    }
}
