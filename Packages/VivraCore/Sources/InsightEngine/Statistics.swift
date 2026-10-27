import Foundation

/// Deterministic statistics helpers. The one random procedure (the
/// bootstrap) takes an explicit seed, so the same data always produces the
/// same report.
enum Statistics {
    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// Linear-interpolated percentile, `p` in 0...1.
    static func percentile(_ sortedValues: [Double], _ p: Double) -> Double {
        precondition(!sortedValues.isEmpty)
        let position = p * Double(sortedValues.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sortedValues.count - 1)
        let fraction = position - Double(lower)
        return sortedValues[lower] + (sortedValues[upper] - sortedValues[lower]) * fraction
    }

    /// Two-sided Mann–Whitney U test (normal approximation with tie and
    /// continuity corrections). Rank-based, so it suits small, skewed and
    /// heavily tied samples, and it needs no random numbers.
    static func mannWhitneyPValue(_ a: [Double], _ b: [Double]) -> Double {
        let n1 = Double(a.count)
        let n2 = Double(b.count)
        let n = n1 + n2
        guard n1 > 0, n2 > 0 else { return 1 }

        // Average ranks, with tie groups recorded for the variance correction.
        let pooled = (a.map { ($0, true) } + b.map { ($0, false) }).sorted { $0.0 < $1.0 }
        var rankSumA = 0.0
        var tieCorrection = 0.0
        var index = 0
        while index < pooled.count {
            var end = index
            while end + 1 < pooled.count && pooled[end + 1].0 == pooled[index].0 { end += 1 }
            let averageRank = Double(index + end) / 2 + 1
            let ties = Double(end - index + 1)
            tieCorrection += ties * ties * ties - ties
            for position in index...end where pooled[position].1 { rankSumA += averageRank }
            index = end + 1
        }

        let u = rankSumA - n1 * (n1 + 1) / 2
        let mean = n1 * n2 / 2
        let variance = n1 * n2 / 12 * ((n + 1) - tieCorrection / (n * (n - 1)))
        guard variance > 0 else { return 1 }
        let z = max(0, abs(u - mean) - 0.5) / variance.squareRoot()
        return min(1, erfc(z / 2.0.squareRoot()))
    }

    /// Percentile bootstrap 95% interval for median(a) − median(b).
    static func bootstrapDifferenceInterval(_ a: [Double], _ b: [Double], resamples: Int, seed: UInt64)
        -> ClosedRange<Double>
    {
        var generator = SplitMix64(seed: seed)
        var differences: [Double] = []
        differences.reserveCapacity(resamples)
        for _ in 0..<resamples {
            let resampledA = (0..<a.count).map { _ in a[Int(generator.next() % UInt64(a.count))] }
            let resampledB = (0..<b.count).map { _ in b[Int(generator.next() % UInt64(b.count))] }
            differences.append(median(resampledA)! - median(resampledB)!)
        }
        differences.sort()
        return percentile(differences, 0.025)...percentile(differences, 0.975)
    }

    /// Benjamini–Hochberg adjusted p-values, in the input order.
    static func benjaminiHochberg(_ pValues: [Double]) -> [Double] {
        let count = pValues.count
        guard count > 0 else { return [] }
        let order = pValues.indices.sorted { pValues[$0] < pValues[$1] }
        var adjusted = [Double](repeating: 1, count: count)
        var runningMinimum = 1.0
        for rank in stride(from: count, through: 1, by: -1) {
            let index = order[rank - 1]
            runningMinimum = min(runningMinimum, pValues[index] * Double(count) / Double(rank))
            adjusted[index] = runningMinimum
        }
        return adjusted
    }
}

extension Statistics {
    /// Average ranks (1-based), ties sharing the mean of their positions.
    static func ranks(_ values: [Double]) -> [Double] {
        let order = values.indices.sorted { values[$0] < values[$1] }
        var ranks = [Double](repeating: 0, count: values.count)
        var start = 0
        while start < order.count {
            var end = start
            while end + 1 < order.count && values[order[end + 1]] == values[order[start]] { end += 1 }
            let rank = Double(start + end) / 2 + 1
            for position in start...end { ranks[order[position]] = rank }
            start = end + 1
        }
        return ranks
    }

    static func pearson(_ x: [Double], _ y: [Double]) -> Double? {
        guard x.count == y.count, x.count > 1, let meanX = mean(x), let meanY = mean(y) else { return nil }
        var covariance = 0.0
        var varianceX = 0.0
        var varianceY = 0.0
        for (a, b) in zip(x, y) {
            covariance += (a - meanX) * (b - meanY)
            varianceX += (a - meanX) * (a - meanX)
            varianceY += (b - meanY) * (b - meanY)
        }
        guard varianceX > 0, varianceY > 0 else { return nil }
        return covariance / (varianceX * varianceY).squareRoot()
    }

    /// Spearman's ρ: Pearson's r on average ranks. Nil when either side is
    /// constant.
    static func spearman(_ x: [Double], _ y: [Double]) -> Double? {
        pearson(ranks(x), ranks(y))
    }

    /// Two-sided p-value and 95% interval for Spearman's ρ via Fisher's z,
    /// with the standard error 1.06 / √(n − 3) (Fieller, Hartley & Pearson,
    /// 1957). Needs n ≥ 4.
    static func spearmanInference(rho: Double, n: Int) -> (pValue: Double, interval: ClosedRange<Double>) {
        let clamped = min(max(rho, -0.999_999), 0.999_999)
        let z = atanh(clamped)
        let standardError = 1.06 / Double(n - 3).squareRoot()
        let pValue = erfc(abs(z) / standardError / 2.0.squareRoot())
        let margin = 1.959_963_985 * standardError
        return (min(1, pValue), tanh(z - margin)...tanh(z + margin))
    }

    /// Mann–Kendall trend test with the tie-corrected variance and a
    /// continuity correction. `values` must be in time order.
    static func mannKendallPValue(_ values: [Double]) -> Double {
        let n = values.count
        guard n >= 3 else { return 1 }
        var s = 0.0
        for i in 0..<(n - 1) {
            for j in (i + 1)..<n {
                if values[j] > values[i] { s += 1 } else if values[j] < values[i] { s -= 1 }
            }
        }
        var tieTerm = 0.0
        for count in Dictionary(grouping: values, by: { $0 }).values.map(\.count) where count > 1 {
            let t = Double(count)
            tieTerm += t * (t - 1) * (2 * t + 5)
        }
        let size = Double(n)
        let variance = (size * (size - 1) * (2 * size + 5) - tieTerm) / 18
        guard variance > 0, s != 0 else { return 1 }
        let z = (abs(s) - 1) / variance.squareRoot()
        return min(1, erfc(z / 2.0.squareRoot()))
    }

    /// Theil–Sen line: the median of pairwise slopes, and the median of
    /// y − slope · x as the intercept.
    static func theilSen(_ points: [(x: Double, y: Double)]) -> (slope: Double, intercept: Double)? {
        guard points.count >= 2 else { return nil }
        var slopes: [Double] = []
        for i in 0..<(points.count - 1) {
            for j in (i + 1)..<points.count where points[j].x != points[i].x {
                slopes.append((points[j].y - points[i].y) / (points[j].x - points[i].x))
            }
        }
        guard let slope = median(slopes) else { return nil }
        return (slope, median(points.map { $0.y - slope * $0.x })!)
    }

    /// Median absolute deviation from the median.
    static func medianAbsoluteDeviation(_ values: [Double]) -> Double? {
        guard let center = median(values) else { return nil }
        return median(values.map { abs($0 - center) })
    }
}

/// A small, fast, seedable generator (Steele et al., 2014). Not for
/// cryptography; used only to make resampling reproducible.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
