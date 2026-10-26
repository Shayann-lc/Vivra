import Foundation
import InsightEngine

/// Turns finding numbers into the exact strings shown to people. The
/// template renderer, the model prompt and the validator all go through
/// here, so a number is written the same way everywhere.
public enum FindingFormatter {
    public static func format(_ value: Double, _ unit: MetricUnit) -> String {
        switch unit {
        case .seconds: duration(value)
        case .beatsPerMinute: "\(rounded(value)) bpm"
        case .milliseconds: "\(rounded(value)) ms"
        case .millilitersPerKilogramMinute: String(format: "%.1f mL/kg/min", value)
        case .minutes: "\(rounded(value)) min"
        case .count: "\(rounded(value))"
        }
    }

    /// "7h 5m", or "45m" under an hour. Rounded to the minute.
    public static func duration(_ seconds: Double) -> String {
        let totalMinutes = rounded(abs(seconds) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    static func rounded(_ value: Double) -> Int {
        Int(value.rounded())
    }
}

/// Numeric tokens in text, normalized ("05" → "5", "41.30" → "41.3",
/// "1,200" → "1200"). Product names that contain digits are ignored.
public enum NumberTokens {
    private static let ignoredTerms = ["VO2", "VO₂"]

    public static func extract(from text: String) -> [String] {
        var cleaned = text
        for term in ignoredTerms {
            cleaned = cleaned.replacingOccurrences(of: term, with: " ", options: .caseInsensitive)
        }
        var tokens: [String] = []
        var current = ""
        func flush() {
            // Drop a trailing separator ("7." at the end of a sentence).
            while let last = current.last, last == "." || last == "," { current.removeLast() }
            if !current.isEmpty { tokens.append(normalize(current)) }
            current = ""
        }
        for character in cleaned {
            if character.isASCII && character.isNumber {
                current.append(character)
            } else if character == "." || character == ",", !current.isEmpty, !current.contains(".") {
                current.append(character)
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }

    static func normalize(_ token: String) -> String {
        let plain = token.replacingOccurrences(of: ",", with: "")
        guard let value = Double(plain) else { return plain }
        if value == value.rounded() { return String(Int(value)) }
        var text = String(format: "%.3f", value)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }
}
