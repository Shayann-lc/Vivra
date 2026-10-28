import Foundation
import InsightEngine
import NarrativeCore

/// The checks every AI-written summary is scored on. Each is deterministic.
/// Where a check depends on wording, it is anchored to the template sentence
/// for the same finding, which is the reference for what may be said.
public enum EvalScorer: String, Codable, Sendable, CaseIterable, Comparable {
    /// `NarrativeValidator`: grounded numbers, no banned or causal language.
    case validator
    /// One bullet per finding, in the given order, none extra or missing.
    case structure
    /// The headline contains no data values (report windows like "7" are fine).
    case headline
    /// Each finding's key values appear in its sentence.
    case keyValues
    /// A rise is never described as a fall, or the other way round.
    case direction
    /// No more sentences per finding than its template uses.
    case sentences
    /// Headline and sentences stay within the app's and the widget's room.
    case length
    /// Each sentence speaks to the reader ("you", "your").
    case secondPerson

    public static func < (lhs: EvalScorer, rhs: EvalScorer) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

public struct EvalIssue: Codable, Sendable, Equatable, CustomStringConvertible {
    public let scorer: EvalScorer
    public let findingID: String?
    public let detail: String

    public init(_ scorer: EvalScorer, findingID: String? = nil, _ detail: String) {
        self.scorer = scorer
        self.findingID = findingID
        self.detail = detail
    }

    public var description: String {
        "[\(scorer.rawValue)\(findingID.map { " \($0)" } ?? "")] \(detail)"
    }
}

public enum EvalScoring {
    /// Longest headline, in characters. The widget shows it on one line.
    public static let maximumHeadlineLength = 60
    /// A sentence may be this much longer than its template before it counts
    /// as rambling.
    public static let lengthAllowance = 1.5
    /// Room in the medium widget for those, in characters. Only the daily
    /// check-in appears on the widget, so only it is held to this.
    public static let maximumWidgetLength = 420

    static let risingWords = [
        "higher", "more", "above", "rose", "risen", "increased", "up", "longer", "greater", "climbed",
    ]
    static let fallingWords = [
        "lower", "less", "fewer", "below", "fell", "fallen", "decreased", "down", "shorter",
        "dropped",
    ]

    public static func score(_ draft: NarrativeDraft, for evalCase: EvalCase) -> [EvalIssue] {
        let findings = evalCase.findings
        guard !findings.isEmpty else {
            // The composer never calls the model for an empty report; the
            // template says there isn't enough data yet.
            var issues: [EvalIssue] = []
            if !draft.bullets.isEmpty { issues.append(EvalIssue(.structure, "An empty report has sentences.")) }
            if draft.headline.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append(EvalIssue(.headline, "The headline is empty."))
            }
            return issues
        }

        var issues = NarrativeValidator.validate(draft, findings: findings).map {
            EvalIssue(.validator, $0.description)
        }
        issues += structure(draft, findings: findings)
        issues += headline(draft)
        issues += length(draft, findings: findings, kind: evalCase.kind)

        let byID = Dictionary(findings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for bullet in draft.bullets {
            guard let finding = byID[bullet.findingID] else { continue }
            let template = TemplateRenderer.sentence(for: finding)
            issues += keyValues(bullet, finding: finding)
            issues += direction(bullet, finding: finding)
            issues += sentences(bullet, template: template)
            if !mentionsReader(bullet.text) {
                issues.append(EvalIssue(.secondPerson, findingID: bullet.findingID, "Doesn't address the reader."))
            }
        }
        return issues.sorted { $0.scorer < $1.scorer }
    }

    // MARK: Checks

    static func structure(_ draft: NarrativeDraft, findings: [Finding]) -> [EvalIssue] {
        let expected = findings.map(\.id)
        let actual = draft.bullets.map(\.findingID)
        if actual == expected { return [] }
        var issues: [EvalIssue] = []
        for id in expected where !actual.contains(id) {
            issues.append(EvalIssue(.structure, findingID: id, "No sentence for this finding."))
        }
        var seen: Set<String> = []
        for id in actual where !seen.insert(id).inserted {
            issues.append(EvalIssue(.structure, findingID: id, "More than one sentence for this finding."))
        }
        if issues.isEmpty {
            issues.append(EvalIssue(.structure, "Findings aren't in the order given."))
        }
        return issues
    }

    static func headline(_ draft: NarrativeDraft) -> [EvalIssue] {
        let text = draft.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return [EvalIssue(.headline, "The headline is empty.")] }
        let values = NumberTokens.extract(from: text).filter { !NarrativeValidator.alwaysAllowedNumbers.contains($0) }
        return values.isEmpty ? [] : [EvalIssue(.headline, "The headline contains \(values.joined(separator: ", ")).")]
    }

    static func length(_ draft: NarrativeDraft, findings: [Finding], kind: ReportKind) -> [EvalIssue] {
        var issues: [EvalIssue] = []
        if draft.headline.count > maximumHeadlineLength {
            issues.append(EvalIssue(.length, "Headline has \(draft.headline.count) characters."))
        }
        let byID = Dictionary(findings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for bullet in draft.bullets {
            guard let finding = byID[bullet.findingID] else { continue }
            let limit = Int(Double(TemplateRenderer.sentence(for: finding).count) * lengthAllowance)
            if bullet.text.count > limit {
                issues.append(
                    EvalIssue(
                        .length, findingID: bullet.findingID,
                        "\(bullet.text.count) characters; the limit for this finding is \(limit)."))
            }
        }
        let widget = WidgetText.make(from: draft)
        if kind == .daily && widget.count > maximumWidgetLength {
            issues.append(EvalIssue(.length, "Widget text has \(widget.count) characters."))
        }
        return issues
    }

    static func keyValues(_ bullet: NarrativeDraft.Bullet, finding: Finding) -> [EvalIssue] {
        var available = NumberTokens.extract(from: bullet.text)
        var missing: [String] = []
        for value in keyValues(of: finding) {
            for token in NumberTokens.extract(from: value) {
                if let index = available.firstIndex(of: token) {
                    available.remove(at: index)
                } else {
                    missing.append(value)
                    break
                }
            }
        }
        return missing.isEmpty
            ? [] : [EvalIssue(.keyValues, findingID: finding.id, "Missing \(missing.joined(separator: ", ")).")]
    }

    /// The values a sentence about the finding must state, formatted as the
    /// templates format them.
    static func keyValues(of finding: Finding) -> [String] {
        func format(_ value: Double, _ metric: Metric) -> String { FindingFormatter.format(value, metric.unit) }
        switch finding.detail {
        case .weeklyAverage(let average): return [format(average.thisWeek, average.metric)]
        case .periodAverage(let average): return [format(average.value, average.metric)]
        case .groupDifference(let difference):
            return [
                format(difference.withConditionMedian, difference.outcome),
                format(difference.withoutConditionMedian, difference.outcome),
            ]
        case .correlation(let correlation):
            return [
                format(correlation.highGroupMedianY, correlation.y),
                format(correlation.lowGroupMedianY, correlation.y),
            ]
        case .trend(let trend): return [format(trend.startValue, trend.metric), format(trend.endValue, trend.metric)]
        case .anomaly(let anomaly): return [format(anomaly.value, anomaly.metric)]
        case .dayComparison(let comparison):
            return [format(comparison.value, comparison.metric), format(comparison.baselineMedian, comparison.metric)]
        case .applicablePattern(let pattern): return [format(pattern.value, pattern.metric)]
        }
    }

    enum Direction { case rising, falling }

    /// The direction a finding reports, when it reports one. Patterns
    /// compare two groups and are worded in the templates without a
    /// direction, so they aren't checked.
    static func direction(of finding: Finding) -> Direction? {
        /// Values that read the same once formatted count as no change.
        func compare(_ now: Double, _ before: Double?, _ metric: Metric) -> Direction? {
            guard let before else { return nil }
            if FindingFormatter.format(now, metric.unit) == FindingFormatter.format(before, metric.unit) { return nil }
            return now > before ? .rising : .falling
        }
        switch finding.detail {
        case .weeklyAverage(let average): return compare(average.thisWeek, average.previousWeek, average.metric)
        case .periodAverage(let average): return compare(average.value, average.previous, average.metric)
        case .trend(let trend): return compare(trend.endValue, trend.startValue, trend.metric)
        case .anomaly(let anomaly): return anomaly.isAbove ? .rising : .falling
        case .dayComparison(let comparison):
            return compare(comparison.value, comparison.baselineMedian, comparison.metric)
        case .groupDifference, .correlation, .applicablePattern: return nil
        }
    }

    static func direction(_ bullet: NarrativeDraft.Bullet, finding: Finding) -> [EvalIssue] {
        guard let expected = direction(of: finding) else { return [] }
        let (right, wrong) = expected == .rising ? (risingWords, fallingWords) : (fallingWords, risingWords)
        let saysRight = right.contains { NarrativeValidator.containsPhrase($0, in: bullet.text) }
        let saysWrong = wrong.filter { NarrativeValidator.containsPhrase($0, in: bullet.text) }
        if saysRight || saysWrong.isEmpty { return [] }
        let actual = expected == .rising ? "rise" : "fall"
        return [
            EvalIssue(
                .direction, findingID: finding.id,
                "Describes a \(actual) with \"\(saysWrong.joined(separator: "\", \""))\".")
        ]
    }

    static func sentences(_ bullet: NarrativeDraft.Bullet, template: String) -> [EvalIssue] {
        let allowed = sentenceCount(template)
        let actual = sentenceCount(bullet.text)
        return actual <= allowed
            ? []
            : [EvalIssue(.sentences, findingID: bullet.findingID, "\(actual) sentences; its template uses \(allowed).")]
    }

    /// Sentence ends followed by more text, plus the final sentence. A full
    /// stop inside a number ("7.4") doesn't end a sentence.
    static func sentenceCount(_ text: String) -> Int {
        let characters = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !characters.isEmpty else { return 0 }
        var count = 1
        for index in characters.indices.dropLast() where ".!?".contains(characters[index]) {
            if characters[index + 1] == " " { count += 1 }
        }
        return count
    }

    static func mentionsReader(_ text: String) -> Bool {
        ["you", "your", "you're", "you've"].contains { NarrativeValidator.containsPhrase($0, in: text) }
    }
}
