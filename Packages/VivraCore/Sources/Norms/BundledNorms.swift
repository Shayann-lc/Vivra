import InsightEngine

extension NormTable {
    /// Shipped in every build. Bump `bundledVersion` whenever values change.
    public static let bundledVersion = 1

    public static let bundled = NormTable(
        sources: [cdcRestingPulse, aasmSleep],
        percentiles: restingPulse,
        recommendations: [
            RecommendationNorm(
                metric: .sleepDuration, ages: 18...60, minimum: 7 * 3600, maximum: nil, sourceID: "aasm-srs-2015")
        ]
    )

    static let cdcRestingPulse = NormSource(
        id: "cdc-nhsr41",
        name: "the CDC's national survey",
        citation:
            "Ostchega Y, Porter KS, Hughes J, Dillon CF, Nwankwo T. Resting Pulse Rate Reference Data for Children, "
            + "Adolescents, and Adults: United States, 1999–2008. National Health Statistics Reports No. 41. "
            + "National Center for Health Statistics, 2011.",
        url: "https://www.cdc.gov/nchs/data/nhsr/nhsr041.pdf",
        caveat:
            "The survey measured pulse while seated after about 4 minutes of rest, in the US in 1999–2008. Apple Watch "
            + "estimates resting heart rate differently, and its values are often lower."
    )

    static let aasmSleep = NormSource(
        id: "aasm-srs-2015",
        name: "the American Academy of Sleep Medicine and Sleep Research Society",
        citation:
            "Watson NF, Badr MS, Belenky G, et al. Recommended Amount of Sleep for a Healthy Adult: A Joint Consensus "
            + "Statement of the American Academy of Sleep Medicine and Sleep Research Society. J Clin Sleep Med. "
            + "2015;11(6):591–592.",
        url: "https://doi.org/10.5664/jcsm.4758",
        caveat: "The recommendation covers adults aged 18–60 and is about sleep on a regular basis, not single nights."
    )

    /// NHSR No. 41, Tables 2 (males) and 3 (females): 5th–95th percentiles, bpm.
    static let restingPulse: [PercentileNorm] = {
        let percentiles = [5, 10, 25, 50, 75, 90, 95]
        let rows: [(ReferenceGroup, ClosedRange<Int>, [Double])] = [
            (.men, 16...19, [52, 56, 61, 69, 78, 87, 92]),
            (.men, 20...39, [52, 55, 61, 69, 76, 84, 89]),
            (.men, 40...59, [52, 55, 61, 68, 77, 85, 90]),
            (.men, 60...79, [50, 54, 60, 67, 75, 84, 91]),
            (.men, 80...120, [51, 54, 61, 68, 78, 86, 94]),
            (.women, 16...19, [58, 62, 69, 77, 85, 94, 99]),
            (.women, 20...39, [57, 60, 66, 74, 82, 89, 95]),
            (.women, 40...59, [56, 59, 64, 71, 79, 86, 92]),
            (.women, 60...79, [56, 59, 64, 70, 78, 86, 92]),
            (.women, 80...120, [56, 59, 64, 71, 77, 85, 93]),
        ]
        return rows.map { group, ages, values in
            PercentileNorm(
                metric: .restingHeartRate,
                group: group,
                ages: ages,
                points: zip(percentiles, values).map { PercentilePoint($0, $1) },
                sourceID: "cdc-nhsr41"
            )
        }
    }()
}
