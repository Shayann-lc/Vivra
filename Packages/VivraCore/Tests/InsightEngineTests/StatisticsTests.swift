import Testing

@testable import InsightEngine

@Suite struct StatisticsTests {
    @Test func medianOfOddAndEvenCounts() {
        #expect(Statistics.median([3, 1, 2]) == 2)
        #expect(Statistics.median([4, 1, 3, 2]) == 2.5)
        #expect(Statistics.median([]) == nil)
    }

    @Test func percentileInterpolates() {
        #expect(Statistics.percentile([0, 10], 0.5) == 5)
        #expect(Statistics.percentile([1, 2, 3, 4, 5], 0.25) == 2)
    }

    /// Known answer: R's p.adjust(c(0.01, 0.04, 0.03, 0.2), "BH")
    /// gives 0.04, 0.0533, 0.0533, 0.2.
    @Test func benjaminiHochbergMatchesReference() {
        let adjusted = Statistics.benjaminiHochberg([0.01, 0.04, 0.03, 0.2])
        let expected = [0.04, 0.16 / 3, 0.16 / 3, 0.2]
        for (value, reference) in zip(adjusted, expected) {
            #expect(abs(value - reference) < 1e-12)
        }
    }

    /// Known answer: scipy.stats.mannwhitneyu([1..5], [6..10],
    /// method="asymptotic", use_continuity=True) gives p = 0.01219.
    @Test func mannWhitneyMatchesReference() {
        let p = Statistics.mannWhitneyPValue([1, 2, 3, 4, 5], [6, 7, 8, 9, 10])
        #expect(abs(p - 0.01219) < 0.0001)
    }

    /// Known answer with ties: scipy gives p = 0.07840 for
    /// [1, 2, 2, 3, 3, 3] vs [2, 3, 3, 4, 4, 5].
    @Test func mannWhitneyHandlesTies() {
        let p = Statistics.mannWhitneyPValue([1, 2, 2, 3, 3, 3], [2, 3, 3, 4, 4, 5])
        #expect(abs(p - 0.07840) < 0.0001)
    }

    @Test func mannWhitneyFindsNothingInIdenticalGroups() {
        let a = (0..<15).map { Double($0) }
        #expect(Statistics.mannWhitneyPValue(a, a) == 1)
        #expect(Statistics.mannWhitneyPValue([5, 5, 5], [5, 5, 5]) == 1)
    }

    @Test func bootstrapIsDeterministic() {
        let a = [1.0, 4, 2, 8, 5, 7]
        let b = [3.0, 9, 6, 2, 8, 4]
        #expect(
            Statistics.bootstrapDifferenceInterval(a, b, resamples: 500, seed: 9)
                == Statistics.bootstrapDifferenceInterval(a, b, resamples: 500, seed: 9)
        )
    }

    @Test func bootstrapIntervalBracketsTheTrueDifference() {
        let a = (0..<20).map { 60 + Double($0 % 5) }
        let b = (0..<20).map { 65 + Double($0 % 5) }
        let interval = Statistics.bootstrapDifferenceInterval(a, b, resamples: 2_000, seed: 3)
        #expect(interval.contains(-5))
        #expect(interval.upperBound < 0)
    }

    /// Reference values from the SplitMix64 reference C implementation, seed 0.
    @Test func splitMixMatchesReference() {
        var generator = SplitMix64(seed: 0)
        #expect(generator.next() == 0xE220_A839_7B1D_CDAF)
        #expect(generator.next() == 0x6E78_9E6A_A1B9_65F4)
    }

    /// Known answers from scipy.stats.spearmanr.
    @Test func spearmanMatchesScipy() {
        let rho = Statistics.spearman([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], [2, 1, 4, 3, 7, 8, 6, 9, 10, 12])!
        #expect(abs(rho - 0.939_393_939) < 1e-9)
        let tied = Statistics.spearman([1, 2, 2, 3, 4, 5, 5, 6], [3, 3, 1, 4, 6, 5, 7, 7])!
        #expect(abs(tied - 0.890_243_902) < 1e-9)
        #expect(Statistics.spearman([1, 1, 1], [1, 2, 3]) == nil)
    }

    /// Reference computed independently in Python from the same formula.
    @Test func spearmanInferenceMatchesReference() {
        let inference = Statistics.spearmanInference(rho: 0.939_393_939_393_939_3, n: 10)
        #expect(abs(inference.pValue - 1.523_768e-5) < 1e-10)
        #expect(abs(inference.interval.lowerBound - 0.738_705_218) < 1e-8)
        #expect(abs(inference.interval.upperBound - 0.987_087_443) < 1e-8)
    }

    /// Known answers from pymannkendall.original_test.
    @Test func mannKendallMatchesReference() {
        let p = Statistics.mannKendallPValue([5.1, 5.3, 5.2, 5.6, 5.8, 5.7, 6.1, 6.0, 6.4, 6.3, 6.6, 6.9])
        #expect(abs(p - 9.281_898e-5) < 1e-10)
        let tied = Statistics.mannKendallPValue([3, 3, 4, 4, 4, 5, 5, 6, 5, 7, 7, 7])
        #expect(abs(tied - 1.829_722e-4) < 1e-9)
        #expect(Statistics.mannKendallPValue([4, 4, 4, 4]) == 1)
    }

    /// Known answer from scipy.stats.theilslopes(method="joint").
    @Test func theilSenMatchesScipy() {
        let points = [2.0, 4, 3, 6, 7, 9, 8].enumerated().map { (x: Double($0), y: $1) }
        let line = Statistics.theilSen(points)!
        #expect(line.slope == 1.25)
        #expect(line.intercept == 2)
    }

    @Test func medianAbsoluteDeviation() {
        #expect(Statistics.medianAbsoluteDeviation([1, 1, 2, 2, 4, 6, 9]) == 1)
        #expect(Statistics.ranks([10, 20, 20, 30]) == [1, 2.5, 2.5, 4])
    }
}
