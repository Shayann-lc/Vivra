import Foundation
import InsightEngine
import VivraLogging

/// A summary as structured sentences, each tied to the finding it restates.
public struct NarrativeDraft: Codable, Sendable, Equatable {
    public struct Bullet: Codable, Sendable, Equatable {
        public let findingID: String
        public let text: String

        public init(findingID: String, text: String) {
            self.findingID = findingID
            self.text = text
        }
    }

    public let headline: String
    public let bullets: [Bullet]

    public init(headline: String, bullets: [Bullet]) {
        self.headline = headline
        self.bullets = bullets
    }
}

public enum NarrativeViolation: Sendable, Equatable, CustomStringConvertible {
    case empty
    case unknownFinding(String)
    case unsupportedNumber(String, findingID: String?)
    case bannedTerm(String)
    case causalLanguage(String)

    /// Written to be fed back to the model in a retry.
    public var description: String {
        switch self {
        case .empty:
            "The summary was empty."
        case .unknownFinding(let id):
            "\"\(id)\" is not one of the finding ids."
        case .unsupportedNumber(let number, let findingID?):
            "The number \(number) does not appear in finding \(findingID)."
        case .unsupportedNumber(let number, nil):
            "The number \(number) in the headline does not appear in any finding."
        case .bannedTerm(let term):
            "The word \"\(term)\" is not allowed."
        case .causalLanguage(let phrase):
            "\"\(phrase)\" implies cause and effect, which is not allowed."
        }
    }
}

public enum NarrativeValidator {
    /// Report windows (7, 28 and 90 days) may always be mentioned.
    static let alwaysAllowedNumbers: Set<String> = ["7", "28", "90"]

    public static func validate(_ draft: NarrativeDraft, findings: [Finding]) -> [NarrativeViolation] {
        var violations: [NarrativeViolation] = []
        if draft.bullets.isEmpty || draft.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            violations.append(.empty)
        }

        let allowedByFinding = Dictionary(
            findings.map { ($0.id, allowedNumbers(for: $0)) },
            uniquingKeysWith: { $0.union($1) }
        )
        let allAllowed = allowedByFinding.values.reduce(alwaysAllowedNumbers) { $0.union($1) }

        for number in NumberTokens.extract(from: draft.headline) where !allAllowed.contains(number) {
            violations.append(.unsupportedNumber(number, findingID: nil))
        }
        for bullet in draft.bullets {
            guard let allowed = allowedByFinding[bullet.findingID] else {
                violations.append(.unknownFinding(bullet.findingID))
                continue
            }
            for number in NumberTokens.extract(from: bullet.text) where !allowed.contains(number) {
                violations.append(.unsupportedNumber(number, findingID: bullet.findingID))
            }
        }

        let allText = ([draft.headline] + draft.bullets.map(\.text)).joined(separator: "\n")
        for term in StyleGuide.bannedTerms where containsPhrase(term, in: allText) {
            violations.append(.bannedTerm(term))
        }
        for phrase in StyleGuide.causalPhrases where containsPhrase(phrase, in: allText) {
            violations.append(.causalLanguage(phrase))
        }
        return violations
    }

    /// The numbers a sentence about `finding` may contain: those in its
    /// template sentence, plus the size of any difference it reports.
    static func allowedNumbers(for finding: Finding) -> Set<String> {
        var allowed = alwaysAllowedNumbers
        allowed.formUnion(NumberTokens.extract(from: TemplateRenderer.sentence(for: finding)))
        func allow(_ value: Double, _ metric: Metric) {
            allowed.formUnion(NumberTokens.extract(from: FindingFormatter.format(abs(value), metric.unit)))
        }
        switch finding.detail {
        case .weeklyAverage(let average):
            if let previous = average.previousWeek { allow(average.thisWeek - previous, average.metric) }
        case .groupDifference(let difference):
            allow(difference.difference, difference.outcome)
        case .correlation(let correlation):
            allow(correlation.highGroupMedianY - correlation.lowGroupMedianY, correlation.y)
        case .trend(let trend):
            allow(trend.endValue - trend.startValue, trend.metric)
        case .anomaly(let anomaly):
            allow(anomaly.value - (anomaly.isAbove ? anomaly.usualHigh : anomaly.usualLow), anomaly.metric)
        case .dayComparison(let comparison):
            allow(comparison.value - comparison.baselineMedian, comparison.metric)
        }
        return allowed
    }

    /// Whole-word, case-insensitive match. Apostrophes count as word
    /// characters, so "don't" doesn't match "don".
    public static func containsPhrase(_ phrase: String, in text: String) -> Bool {
        let haystack = text.lowercased()
        let needle = phrase.lowercased()
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let match = haystack.range(of: needle, range: searchRange) {
            let before =
                match.lowerBound == haystack.startIndex ? nil : haystack[haystack.index(before: match.lowerBound)]
            let after = match.upperBound == haystack.endIndex ? nil : haystack[match.upperBound]
            if !isWordCharacter(before) && !isWordCharacter(after) { return true }
            searchRange = match.upperBound..<haystack.endIndex
        }
        return false
    }

    private static func isWordCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber || character == "'" || character == "’"
    }
}
