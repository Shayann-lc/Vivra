import Foundation
import InsightEngine
import Testing
import VivraModel

@testable import NarrativeCore

private let caffeinePattern = Finding(
    id: "pattern.caffeine.sleepDuration.lag1",
    detail: .correlation(
        Correlation(
            x: .caffeine,
            y: .sleepDuration,
            lag: 1,
            rho: -0.52,
            rhoLow: -0.7,
            rhoHigh: -0.3,
            days: 60,
            pValue: 0.0001,
            adjustedPValue: 0.001,
            confidence: .high,
            split: .thirds,
            lowGroupMaxX: 60,
            highGroupMinX: 190,
            lowGroupMedianY: 7.25 * 3600,
            highGroupMedianY: 6.6667 * 3600,
            lowGroupDays: 20,
            highGroupDays: 20
        )
    )
)
private let alcoholPattern = Finding(
    id: "pattern.alcohol.heartRateVariability.lag1",
    detail: .correlation(
        Correlation(
            x: .alcohol,
            y: .heartRateVariability,
            lag: 1,
            rho: -0.41,
            rhoLow: -0.6,
            rhoHigh: -0.2,
            days: 52,
            pValue: 0.002,
            adjustedPValue: 0.02,
            confidence: .medium,
            split: .noneVersusSome,
            lowGroupMaxX: 0,
            highGroupMinX: 1,
            lowGroupMedianY: 46,
            highGroupMedianY: 38,
            lowGroupDays: 35,
            highGroupDays: 17
        )
    )
)
private let sleepMoodPattern = Finding(
    id: "pattern.sleepDuration.mood.lag0",
    detail: .correlation(
        Correlation(
            x: .sleepDuration,
            y: .mood,
            lag: 0,
            rho: 0.45,
            rhoLow: 0.2,
            rhoHigh: 0.65,
            days: 40,
            pValue: 0.003,
            adjustedPValue: 0.03,
            confidence: .low,
            split: .thirds,
            lowGroupMaxX: 6.2 * 3600,
            highGroupMinX: 7.5 * 3600,
            lowGroupMedianY: 3,
            highGroupMedianY: 4,
            lowGroupDays: 14,
            highGroupDays: 14
        )
    )
)
private let stepsTrend = Finding(
    id: "trend.steps",
    detail: .trend(
        Trend(
            metric: .steps,
            windowDays: 28,
            startValue: 7_214,
            endValue: 9_106,
            days: 27,
            pValue: 0.001,
            adjustedPValue: 0.004,
            confidence: .high
        )
    )
)
private let restingAnomaly = Finding(
    id: "anomaly.restingHeartRate",
    detail: .anomaly(
        Anomaly(metric: .restingHeartRate, daysAgo: 0, value: 71, usualLow: 56.2, usualHigh: 61.8, baselineDays: 27)
    )
)
private let sleepComparison = Finding(
    id: "today.sleepDuration",
    detail: .dayComparison(
        DayComparison(
            metric: .sleepDuration, daysAgo: 0, value: 6.5 * 3600, baselineMedian: 7.25 * 3600, baselineDays: 28)
    )
)
private let moodComparison = Finding(
    id: "today.mood",
    detail: .dayComparison(DayComparison(metric: .mood, daysAgo: 1, value: 4, baselineMedian: 3.5, baselineDays: 20))
)

@Suite struct PhaseTwoTemplateTests {
    @Test func everyMetricAndKindPassesTheValidator() {
        var findings = [caffeinePattern, alcoholPattern, sleepMoodPattern, stepsTrend, restingAnomaly, sleepComparison]
        for metric in Metric.allCases {
            let value: Double =
                switch metric.unit {
                case .seconds: 25_000
                case .percent: 96
                case .scale: 3.4
                case .degreesCelsius: 36.15
                default: 1_234.5
                }
            findings.append(
                Finding(
                    id: "average.\(metric.rawValue)",
                    detail: .weeklyAverage(
                        WeeklyAverage(
                            metric: metric, thisWeek: value, thisWeekDays: 5, previousWeek: value * 0.9,
                            previousWeekDays: 6)
                    )
                )
            )
            findings.append(
                Finding(
                    id: "trendOf.\(metric.rawValue)",
                    detail: .trend(
                        Trend(
                            metric: metric, windowDays: 28, startValue: value, endValue: value * 1.2, days: 20,
                            pValue: 0.01, adjustedPValue: 0.02, confidence: .medium)
                    )
                )
            )
            findings.append(
                Finding(
                    id: "comparison.\(metric.rawValue)",
                    detail: .dayComparison(
                        DayComparison(
                            metric: metric, daysAgo: 1, value: value, baselineMedian: value * 0.8, baselineDays: 21))
                )
            )
        }
        for kind in [ReportKind.weekly, .daily] {
            let draft = TemplateRenderer.render(findings, kind: kind)
            #expect(NarrativeValidator.validate(draft, findings: findings) == [])
        }
    }

    @Test func correlationGoldens() {
        #expect(
            TemplateRenderer.sentence(for: caffeinePattern)
                == "On days with 190 mg or more of caffeine, you slept a median of 6h 40m the following night, "
                + "compared with 7h 15m on days with 60 mg or less of caffeine (60 days compared, high confidence)."
        )
        #expect(
            TemplateRenderer.sentence(for: alcoholPattern)
                == "On days with any alcohol, your heart rate variability (SDNN) the next day had a median of 38 ms, "
                + "compared with 46 ms on days with no alcohol (52 days compared, medium confidence)."
        )
        #expect(
            TemplateRenderer.sentence(for: sleepMoodPattern)
                == "After a night of 7h 30m or more, your mood had a median of 4 out of 5, "
                + "compared with 3 out of 5 after a night of 6h 12m or less (40 days compared, low confidence)."
        )
    }

    @Test func trendAnomalyAndComparisonGoldens() {
        #expect(
            TemplateRenderer.sentence(for: stepsTrend)
                == "Over the last 28 days, your daily step count went from about 7,214 steps to about 9,106 steps "
                + "(27 days recorded, high confidence)."
        )
        #expect(
            TemplateRenderer.sentence(for: restingAnomaly)
                == "Your resting heart rate today was 71 bpm, above your usual range of 56–62 bpm over the previous 27 days."
        )
        #expect(
            TemplateRenderer.sentence(for: sleepComparison)
                == "Last night you slept 6h 30m. Your median over the previous 28 nights is 7h 15m."
        )
        #expect(
            TemplateRenderer.sentence(for: moodComparison)
                == "Your mood yesterday was 4 out of 5. Your median over the previous 20 days is 3.5 out of 5."
        )
    }

    @Test func dailyKindHasItsOwnHeadlines() {
        #expect(TemplateRenderer.render([sleepComparison], kind: .daily).headline == "Today's check-in")
        #expect(TemplateRenderer.render([], kind: .daily).headline == "Not enough data for a check-in yet")
        #expect(PromptBuilder.prompt(kind: .daily, findings: [sleepComparison], corrections: []).contains("check-in"))
    }

    @Test func allowsTheSizeOfAReportedChange() {
        let draft = NarrativeDraft(
            headline: "Today",
            bullets: [
                .init(
                    findingID: "anomaly.restingHeartRate",
                    text: "Your resting heart rate today was 71 bpm, 9 bpm above your usual range."),
                .init(findingID: "today.sleepDuration", text: "You slept 6h 30m, 45m less than your median."),
            ]
        )
        #expect(NarrativeValidator.validate(draft, findings: [restingAnomaly, sleepComparison]) == [])
    }

    @Test func formatsNewUnits() {
        #expect(FindingFormatter.format(12_345.4, .steps) == "12,345 steps")
        #expect(FindingFormatter.format(5_240, .meters) == "5.2 km")
        #expect(FindingFormatter.format(4, .scale) == "4 out of 5")
        #expect(FindingFormatter.format(1, .drinks) == "1 drink")
        #expect(FindingFormatter.format(1.5, .drinks) == "1.5 drinks")
        #expect(FindingFormatter.format(96, .percent) == "96%")
        #expect(FindingFormatter.format(36.149, .degreesCelsius) == "36.15 °C")
        #expect(FindingFormatter.format(1, .hours) == "1 stand hour")
        #expect(FindingFormatter.grouped(1_234_567) == "1,234,567")
    }
}

@Suite struct MetricDescriptionTests {
    @Test func descriptionsFollowTheStyleGuide() {
        for metric in Metric.allCases {
            let text = MetricDescriptions.title(metric) + " " + MetricDescriptions.description(metric)
            for term in StyleGuide.bannedTerms + StyleGuide.causalPhrases {
                #expect(!NarrativeValidator.containsPhrase(term, in: text), "\"\(term)\" in \(metric)")
            }
        }
        #expect(MetricDescriptions.title(.restingHeartRate) == "Resting heart rate")
    }
}
