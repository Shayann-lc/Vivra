#if VIVRA_NONCOMMERCIAL
    import Norms

    /// FRIEND treadmill VO2 max medians: the owner's non-commercial build only
    /// (PLAN decision 10, docs/NORMS.md). This file compiles to nothing unless
    /// `VIVRA_NONCOMMERCIAL` is set, so other builds contain none of this data.
    ///
    /// Source: Kaminsky LA, Arena R, Myers J. Mayo Clin Proc. 2015;90(11):1515–1523,
    /// Table 3, 50th percentile (from the author manuscript, PMC4919021).
    extension NormTable {
        static let friendMedians: NormTable = {
            let source = NormSource(
                id: "friend-2015",
                name: "the FRIEND registry",
                citation:
                    "Kaminsky LA, Arena R, Myers J. Reference Standards for Cardiorespiratory Fitness Measured With "
                    + "Cardiopulmonary Exercise Testing: Data From the Fitness Registry and the Importance of Exercise "
                    + "National Database. Mayo Clin Proc. 2015;90(11):1515–1523.",
                url: "https://doi.org/10.1016/j.mayocp.2015.07.026",
                caveat:
                    "FRIEND measured VO2 max in lab treadmill tests in the US in 2014–2015. Apple Watch estimates it from "
                    + "outdoor walks and runs, so values aren't directly comparable. A 2022 update reports treadmill "
                    + "values 1.5–4.6 mL/kg/min lower."
            )
            let rows: [(ReferenceGroup, ClosedRange<Int>, Double)] = [
                (.men, 20...29, 48.0), (.men, 30...39, 42.4), (.men, 40...49, 37.8),
                (.men, 50...59, 32.6), (.men, 60...69, 28.2), (.men, 70...79, 24.4),
                (.women, 20...29, 37.6), (.women, 30...39, 30.2), (.women, 40...49, 26.7),
                (.women, 50...59, 23.4), (.women, 60...69, 20.0), (.women, 70...79, 18.3),
            ]
            return NormTable(
                sources: [source],
                medians: rows.map {
                    MedianNorm(metric: .vo2Max, group: $0.0, ages: $0.1, median: $0.2, sourceID: source.id)
                }
            )
        }()
    }
#endif
