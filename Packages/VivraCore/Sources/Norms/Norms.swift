import Foundation
import InsightEngine

/// Published reference data, compared neutrally and always cited. Sources,
/// licences and caveats: docs/NORMS.md. Values were copied from the primary
/// sources; tests pin a sample of rows.
public enum ReferenceGroup: String, Codable, Sendable, CaseIterable {
    case women
    case men
}

public struct NormSource: Sendable, Equatable, Identifiable {
    public let id: String
    /// How the source is named in sentences.
    public let name: String
    public let citation: String
    public let url: String
    /// What to keep in mind when comparing, shown under every comparison.
    public let caveat: String

    public init(id: String, name: String, citation: String, url: String, caveat: String) {
        self.id = id
        self.name = name
        self.citation = citation
        self.url = url
        self.caveat = caveat
    }
}

public struct PercentilePoint: Sendable, Equatable {
    public let percentile: Int
    public let value: Double

    public init(_ percentile: Int, _ value: Double) {
        self.percentile = percentile
        self.value = value
    }
}

/// Percentiles for one metric, group and age band, in increasing order.
public struct PercentileNorm: Sendable, Equatable {
    public let metric: Metric
    public let group: ReferenceGroup
    public let ages: ClosedRange<Int>
    public let points: [PercentilePoint]
    public let sourceID: String

    public init(
        metric: Metric, group: ReferenceGroup, ages: ClosedRange<Int>, points: [PercentilePoint], sourceID: String
    ) {
        self.metric = metric
        self.group = group
        self.ages = ages
        self.points = points
        self.sourceID = sourceID
    }
}

/// A published recommendation for everyone in an age band.
public struct RecommendationNorm: Sendable, Equatable {
    public let metric: Metric
    public let ages: ClosedRange<Int>
    public let minimum: Double?
    public let maximum: Double?
    public let sourceID: String

    public init(metric: Metric, ages: ClosedRange<Int>, minimum: Double?, maximum: Double?, sourceID: String) {
        self.metric = metric
        self.ages = ages
        self.minimum = minimum
        self.maximum = maximum
        self.sourceID = sourceID
    }
}

/// A single median for one metric, group and age band.
public struct MedianNorm: Sendable, Equatable {
    public let metric: Metric
    public let group: ReferenceGroup
    public let ages: ClosedRange<Int>
    public let median: Double
    public let sourceID: String

    public init(metric: Metric, group: ReferenceGroup, ages: ClosedRange<Int>, median: Double, sourceID: String) {
        self.metric = metric
        self.group = group
        self.ages = ages
        self.median = median
        self.sourceID = sourceID
    }
}

public struct NormTable: Sendable, Equatable {
    public var sources: [NormSource]
    public var percentiles: [PercentileNorm]
    public var recommendations: [RecommendationNorm]
    public var medians: [MedianNorm]

    public init(
        sources: [NormSource] = [],
        percentiles: [PercentileNorm] = [],
        recommendations: [RecommendationNorm] = [],
        medians: [MedianNorm] = []
    ) {
        self.sources = sources
        self.percentiles = percentiles
        self.recommendations = recommendations
        self.medians = medians
    }

    public func merging(_ other: NormTable) -> NormTable {
        NormTable(
            sources: sources + other.sources,
            percentiles: percentiles + other.percentiles,
            recommendations: recommendations + other.recommendations,
            medians: medians + other.medians
        )
    }

    public func source(_ id: String) -> NormSource? { sources.first { $0.id == id } }

    /// Metrics with any reference data.
    public var metrics: Set<Metric> {
        Set(percentiles.map(\.metric) + recommendations.map(\.metric) + medians.map(\.metric))
    }
}

/// Birth year and the reference tables the person chose. Comparisons stay
/// off until both are set.
public struct ComparisonProfile: Codable, Sendable, Equatable {
    public let birthYear: Int
    public let group: ReferenceGroup

    public init(birthYear: Int, group: ReferenceGroup) {
        self.birthYear = birthYear
        self.group = group
    }

    /// Age this year. Can be a year high before the birthday; age bands are
    /// wide enough that this rarely matters, and the UI says "about".
    public func age(in year: Int) -> Int { year - birthYear }
}
