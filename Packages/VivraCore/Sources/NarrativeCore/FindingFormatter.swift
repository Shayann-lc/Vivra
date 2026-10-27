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
        case .millilitersPerKilogramMinute: "\(decimal(value, places: 1, trim: false)) mL/kg/min"
        case .minutes: "\(grouped(rounded(value))) min"
        case .count: grouped(rounded(value))
        case .steps: "\(grouped(rounded(value))) steps"
        case .kilocalories: "\(grouped(rounded(value))) kcal"
        case .meters: "\(decimal(value / 1000, places: 1, trim: false)) km"
        case .hours: rounded(value) == 1 ? "1 stand hour" : "\(rounded(value)) stand hours"
        case .scale: "\(decimal(value, places: 1)) out of 5"
        case .grams: "\(grouped(rounded(value))) g"
        case .milliliters: "\(grouped(rounded(value))) mL"
        case .milligrams: "\(grouped(rounded(value))) mg"
        case .drinks: decimal(value, places: 1) == "1" ? "1 drink" : "\(decimal(value, places: 1)) drinks"
        case .kilograms: "\(decimal(value, places: 1, trim: false)) kg"
        case .percent: "\(decimal(value, places: 1))%"
        case .breathsPerMinute: "\(decimal(value, places: 1, trim: false)) breaths/min"
        case .degreesCelsius: "\(decimal(value, places: 2, trim: false)) °C"
        }
    }

    /// "56–62 bpm": the unit once, when both ends share it.
    public static func range(_ low: Double, _ high: Double, _ unit: MetricUnit) -> String {
        var lowText = format(low, unit)
        let highText = format(high, unit)
        if unit != .seconds, let space = lowText.firstIndex(of: " ") {
            let suffix = lowText[space...]
            if highText.hasSuffix(suffix) { lowText = String(lowText[..<space]) }
        }
        return "\(lowText)–\(highText)"
    }

    /// "7h 5m", or "45m" under an hour. Rounded to the minute.
    public static func duration(_ seconds: Double) -> String {
        let totalMinutes = rounded(abs(seconds) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    public static func rounded(_ value: Double) -> Int {
        Int(value.rounded())
    }

    /// Fixed decimal places, with trailing zeros dropped when `trim` is set.
    /// Locale-independent, so the validator sees exactly what was written.
    static func decimal(_ value: Double, places: Int, trim: Bool = true) -> String {
        var text = String(format: "%.\(places)f", value)
        if trim, text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }

    /// Thousands separated with commas: 12,345.
    static func grouped(_ value: Int) -> String {
        let digits = String(abs(value))
        var groups: [Substring] = []
        var end = digits.endIndex
        while end > digits.startIndex {
            let start = digits.index(end, offsetBy: -3, limitedBy: digits.startIndex) ?? digits.startIndex
            groups.insert(digits[start..<end], at: 0)
            end = start
        }
        return (value < 0 ? "-" : "") + groups.joined(separator: ",")
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
