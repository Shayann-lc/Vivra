import Foundation
import Testing
import VivraModel

@testable import InsightEngine
@testable import NarrativeCore

/// Every Connections string, for every check, status, split and side, follows
/// the style guide, and every number in it comes from the engine.
@Suite struct ConnectionLabelsTests {
    /// A plausible value of each metric, so formatted numbers look real.
    private static func typical(_ metric: Metric) -> (low: Double, high: Double) {
        switch metric {
        case .sleepDuration: (6.8 * 3600, 7.45 * 3600)
        case .restingHeartRate: (56, 59)
        case .heartRateVariability: (44, 54)
        case .mood, .energyLevel, .stressLevel: (3, 4)
        case .alcohol: (0, 2)
        case .caffeine: (95, 190)
        case .steps: (6_200, 10_400)
        case .exerciseMinutes: (12, 38)
        case .mindfulMinutes: (0, 10)
        case .workoutMinutes: (0, 20)
        default: (1, 2)
        }
    }

    private static func correlation(_ pair: PatternCatalog.Pair, split: Correlation.Split, confidence: Confidence)
        -> Finding
    {
        let x = typical(pair.x)
        let y = typical(pair.y)
        return Finding(
            id: pair.id,
            detail: .correlation(
                Correlation(
                    x: pair.x, y: pair.y, lag: pair.lag, rho: -0.42, rhoLow: -0.6, rhoHigh: -0.2, days: 84,
                    pValue: 0.001, adjustedPValue: 0.004, confidence: confidence, split: split,
                    lowGroupMaxX: split == .noneVersusSome ? 0 : x.low, highGroupMinX: x.high,
                    lowGroupMedianY: y.high, highGroupMedianY: y.low, lowGroupDays: 28, highGroupDays: 27)))
    }

    private static func group(_ condition: Condition, confidence: Confidence) -> Finding {
        let outcome: Metric = condition == .shorterSleep ? .restingHeartRate : .sleepDuration
        let y = typical(outcome)
        return Finding(
            id: condition == .shorterSleep
                ? "pattern.shorterSleep.restingHeartRate" : "pattern.workoutDay.sleepDuration",
            detail: .groupDifference(
                GroupDifference(
                    condition: condition,
                    conditionThreshold: condition == .shorterSleep ? 7.08 * 3600 : 20,
                    outcome: outcome, withConditionMedian: y.high, withoutConditionMedian: y.low,
                    withConditionDays: 41, withoutConditionDays: 44,
                    differenceLow: (y.high - y.low) * 0.4, differenceHigh: (y.high - y.low) * 1.6,
                    pValue: 0.001, adjustedPValue: 0.004, confidence: confidence)))
    }

    /// Every check with every status, found ones in each split, confidence
    /// and side.
    private static let rows: [ConnectionBoard.Row] = {
        var findings: [(ConnectionBehaviour, Metric, Int, Finding)] = []
        for pair in PatternCatalog.correlations {
            for split in [Correlation.Split.thirds, .noneVersusSome] {
                for confidence in [Confidence.low, .medium, .high] {
                    findings.append(
                        (.metric(pair.x), pair.y, pair.lag, correlation(pair, split: split, confidence: confidence)))
                }
            }
        }
        for condition in [Condition.shorterSleep, .workoutDay] {
            for confidence in [Confidence.low, .medium, .high] {
                let finding = group(condition, confidence: confidence)
                let outcome: Metric = condition == .shorterSleep ? .restingHeartRate : .sleepDuration
                findings.append((.condition(condition), outcome, condition == .workoutDay ? 1 : 0, finding))
            }
        }
        var rows: [ConnectionBoard.Row] = []
        for (behaviour, outcome, lag, finding) in findings {
            for latest in [
                nil, ConnectionBoard.Latest(daysAgo: 0, value: typical(behaviour.metric).low, side: .less),
                ConnectionBoard.Latest(daysAgo: 1, value: typical(behaviour.metric).high, side: .more),
            ] {
                rows.append(
                    ConnectionBoard.Row(
                        id: finding.id, behaviour: behaviour, outcome: outcome, lag: lag, status: .found(finding),
                        latest: latest, sortKey: 1))
            }
            let others: [ConnectionStatus] = [
                .noClearPattern(days: 84), .notEnoughVariety(days: 61), .needsMoreDays(have: 6, need: 14),
                .notRecorded(behaviour.metric), .notRecorded(outcome),
            ]
            for status in others {
                rows.append(
                    ConnectionBoard.Row(
                        id: finding.id, behaviour: behaviour, outcome: outcome, lag: lag, status: status, latest: nil,
                        sortKey: 0))
            }
        }
        return rows
    }()

    private static let usual = ConnectionBoard.Usual(
        median: 7 * 3600, low: 6.33 * 3600, high: 7.75 * 3600, axisLow: 6 * 3600, axisHigh: 8 * 3600, days: 84)

    /// The strings shown for a row.
    private static func strings(_ row: ConnectionBoard.Row) -> [String] {
        var strings = [
            ConnectionLabels.title(row), ConnectionLabels.timing(row), ConnectionLabels.status(row),
            ConnectionLabels.accessibilitySentence(row), ConnectionLabels.behaviourName(row.behaviour),
            ConnectionLabels.outcomeName(row.outcome), ConnectionLabels.timelineNote(row),
        ]
        strings += [ConnectionLabels.comparison(row), ConnectionLabels.evidence(row)].compactMap { $0 }
        if let latest = row.latest { strings.append(ConnectionLabels.latest(latest, behaviour: row.behaviour)) }
        if let finding = row.status.finding {
            strings += ConnectionLabels.method(finding)
            if let groups = ConnectionLabels.groups(finding) { strings += [groups.less, groups.more] }
        }
        return strings
    }

    private static let fixedText =
        ConnectionLabels.explainer + [
            ConnectionLabels.footer, ConnectionLabels.lowDataNote, ConnectionLabels.noneFoundNote,
            ConnectionLabels.usual(usual, .sleepDuration),
            ConnectionLabels.rangePosition(1, low: 2, high: 3), ConnectionLabels.rangePosition(2, low: 2, high: 3),
            ConnectionLabels.rangePosition(4, low: 2, high: 3),
        ]

    @Test func followsTheStyleGuide() {
        var checked = 0
        for text in Self.rows.flatMap(Self.strings) + Self.fixedText {
            for term in StyleGuide.bannedTerms + StyleGuide.causalPhrases {
                #expect(!NarrativeValidator.containsPhrase(term, in: text), "\"\(term)\" in: \(text)")
            }
            checked += 1
        }
        #expect(checked > 1_000)
    }

    /// Numbers come from the row's finding, its counts, or the fixed rules
    /// (90 days, 14 days, 17 checks, 95% range).
    @Test func everyNumberComesFromTheEngine() {
        let fixed: Set<String> = ["90", "14", "17", "95"]
        for row in Self.rows {
            var allowed = fixed
            switch row.status {
            case .found(let finding):
                allowed.formUnion(NarrativeValidator.allowedNumbers(for: finding))
                if case .correlation(let correlation) = finding.detail {
                    allowed.formUnion([String(correlation.lowGroupDays), String(correlation.highGroupDays)])
                }
                if case .groupDifference(let difference) = finding.detail {
                    for value in [difference.differenceLow, difference.differenceHigh] {
                        allowed.formUnion(
                            NumberTokens.extract(from: FindingFormatter.format(abs(value), difference.outcome.unit)))
                    }
                }
                if let latest = row.latest {
                    allowed.formUnion(
                        NumberTokens.extract(from: FindingFormatter.format(latest.value, row.behaviour.metric.unit)))
                }
            case .noClearPattern(let days), .notEnoughVariety(let days):
                allowed.insert(String(days))
            case .needsMoreDays(let have, let need):
                allowed.formUnion([String(have), String(need)])
            case .notRecorded:
                break
            }
            for text in Self.strings(row) {
                for token in NumberTokens.extract(from: text) {
                    #expect(allowed.contains(token), "\(token) in: \(text)")
                }
            }
        }
    }

    @Test func notFoundRowsShowNoOutcomeValues() {
        for row in Self.rows where row.status.finding == nil {
            #expect(ConnectionLabels.comparison(row) == nil)
            #expect(ConnectionLabels.evidence(row) == nil)
        }
    }

    @Test func wording() throws {
        let caffeine = try #require(PatternCatalog.correlations.first { $0.x == .caffeine })
        let finding = Self.correlation(caffeine, split: .thirds, confidence: .medium)
        let row = ConnectionBoard.Row(
            id: finding.id, behaviour: .metric(.caffeine), outcome: .sleepDuration, lag: 1, status: .found(finding),
            latest: .init(daysAgo: 1, value: 190, side: .more), sortKey: 1)
        #expect(ConnectionLabels.title(row) == "Caffeine and sleep the night after")
        #expect(ConnectionLabels.comparison(row) == "95 mg or less: 7h 27m · 190 mg or more: 6h 48m")
        #expect(ConnectionLabels.evidence(row) == "28 and 27 days · medium confidence")
        #expect(ConnectionLabels.latest(row.latest!, behaviour: row.behaviour) == "Yesterday 190 mg")

        let alcohol = try #require(
            PatternCatalog.correlations.first { $0.x == .alcohol && $0.y == .heartRateVariability })
        let none = Self.correlation(alcohol, split: .noneVersusSome, confidence: .high)
        let alcoholRow = ConnectionBoard.Row(
            id: none.id, behaviour: .metric(.alcohol), outcome: .heartRateVariability, lag: 1, status: .found(none),
            latest: nil, sortKey: 1)
        #expect(ConnectionLabels.comparison(alcoholRow) == "none: 54 ms · any: 44 ms")
        #expect(ConnectionLabels.title(alcoholRow) == "Alcohol and heart rate variability (SDNN) the next day")

        let sleepMood = ConnectionBoard.Row(
            id: "x", behaviour: .metric(.sleepDuration), outcome: .mood, lag: 0,
            status: .needsMoreDays(have: 6, need: 14),
            latest: nil, sortKey: 0)
        #expect(ConnectionLabels.title(sleepMood) == "Sleep and mood the day after")
        #expect(ConnectionLabels.status(sleepMood) == "Needs more days (6 of 14)")
        #expect(
            ConnectionLabels.accessibilitySentence(sleepMood)
                == "Sleep and mood the day after: needs more days (6 of 14).")
    }

    @Test func summaryCountsEachKindOfRow() {
        let found = Self.rows.first { $0.status.finding != nil }!
        let unclear = Self.rows.first { $0.status == .noClearPattern(days: 84) }!
        let waiting = Self.rows.first { $0.status == .needsMoreDays(have: 6, need: 14) }!
        let board = ConnectionBoard(rows: [found, unclear, unclear, waiting], usual: [:], windowDays: 90)
        #expect(
            ConnectionLabels.summary(board)
                == "Last 90 days: 1 found, 2 with no clear pattern, 1 without enough data yet")
    }
}
