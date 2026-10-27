import InsightEngine
import NarrativeCore
import Testing

@testable import Norms

@Suite struct NormsTests {
    private let table = NormTable.bundled

    /// Values copied from NHSR No. 41 Tables 2 and 3 (see docs/NORMS.md).
    @Test func restingPulseMatchesThePrimarySource() throws {
        func points(_ group: ReferenceGroup, _ age: Int) throws -> [Double] {
            try #require(table.percentiles.first { $0.group == group && $0.ages.contains(age) }).points.map(\.value)
        }
        #expect(try points(.men, 45) == [52, 55, 61, 68, 77, 85, 90])
        #expect(try points(.women, 25) == [57, 60, 66, 74, 82, 89, 95])
        #expect(try points(.women, 85) == [56, 59, 64, 71, 77, 85, 93])
    }

    @Test func everyNormHasASourceWithACitation() {
        let ids =
            table.percentiles.map(\.sourceID) + table.recommendations.map(\.sourceID) + table.medians.map(\.sourceID)
        for id in ids {
            let source = table.source(id)
            #expect(source != nil, "\(id)")
            #expect(source?.citation.isEmpty == false)
            #expect(source?.caveat.isEmpty == false)
        }
        #expect(table.metrics == [.restingHeartRate, .sleepDuration])
        #expect(table.medians.isEmpty, "VO2 max medians must only come from the non-commercial build")
    }

    @Test func percentilesIncreaseWithinEveryRow() {
        for norm in table.percentiles {
            #expect(
                zip(norm.points, norm.points.dropFirst()).allSatisfy {
                    $0.value <= $1.value && $0.percentile < $1.percentile
                })
        }
    }

    @Test func placementCoversEveryCase() {
        let points = [
            PercentilePoint(5, 52), PercentilePoint(10, 55), PercentilePoint(25, 61), PercentilePoint(50, 68),
        ]
        #expect(NormComparer.placement(48, in: points) == .below(5))
        #expect(NormComparer.placement(55.3, in: points) == .at(10))
        #expect(NormComparer.placement(58, in: points) == .between(10, 25))
        #expect(NormComparer.placement(80, in: points) == .above(50))
    }

    @Test func comparesForTheRightGroupAndAge() throws {
        let profile = ComparisonProfile(birthYear: 1980, group: .men)
        let results = NormComparer.compare(.restingHeartRate, value: 58, profile: profile, year: 2026, table: table)
        let first = try #require(results.first)
        guard case .percentile(let placement, let norm, _) = first else {
            Issue.record("Not a percentile")
            return
        }
        #expect(norm.ages == 40...59)
        #expect(placement == .between(10, 25))
        #expect(NormComparer.compare(.restingHeartRate, value: 58, profile: profile, year: 1995, table: table).isEmpty)
    }

    @Test func sleepRecommendationOnlyCoversItsAges() {
        let young = ComparisonProfile(birthYear: 1990, group: .women)
        let older = ComparisonProfile(birthYear: 1950, group: .women)
        #expect(
            NormComparer.compare(.sleepDuration, value: 25_000, profile: young, year: 2026, table: table).count == 1)
        #expect(NormComparer.compare(.sleepDuration, value: 25_000, profile: older, year: 2026, table: table).isEmpty)
    }

    @Test func sentencesAreNeutralAndFollowTheStyleGuide() throws {
        let profile = ComparisonProfile(birthYear: 1980, group: .men)
        let heart = try #require(
            NormComparer.compare(.restingHeartRate, value: 58, profile: profile, year: 2026, table: table).first
        )
        let heartText = NormText.sentence(heart, subject: "Your 28-day median of 58 bpm", valueText: "58 bpm")
        #expect(
            heartText
                == "Your 28-day median of 58 bpm is between the 10th and 25th percentiles for men aged 40–59 in the CDC's national survey."
        )
        let sleep = try #require(
            NormComparer.compare(.sleepDuration, value: 24_000, profile: profile, year: 2026, table: table).first
        )
        let sleepText = NormText.sentence(sleep, subject: "Your 28-day median", valueText: "6h 40m")
        #expect(
            sleepText
                == "The American Academy of Sleep Medicine and Sleep Research Society recommend 7 hours or more for adults aged 18–60. Your 28-day median is 6h 40m."
        )
        let median = NormComparison.median(
            MedianNorm(metric: .vo2Max, group: .women, ages: 30...39, median: 30.2, sourceID: "x"),
            source: NormSource(id: "x", name: "a registry", citation: "c", url: "u", caveat: "v")
        )
        let medianText = NormText.sentence(median, subject: "Your latest estimate", valueText: "33.1 mL/kg/min")
        let texts = [heartText, sleepText, medianText] + table.sources.map(\.caveat)
        for text in texts {
            for term in StyleGuide.bannedTerms + StyleGuide.causalPhrases {
                #expect(!NarrativeValidator.containsPhrase(term, in: text), "\"\(term)\" in \(text)")
            }
        }
        #expect(
            NormText.ordinal(11) == "11th" && NormText.ordinal(22) == "22nd" && NormText.ages(80...120) == "80 and over"
        )
    }
}
