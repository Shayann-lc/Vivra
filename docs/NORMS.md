# Reference norms: sources, licences and caveats

Vivra compares a person's own values with published reference data only where
the source allows it, and it cites the source wherever a comparison is shown.
Every row below was checked against the primary source (October 2026).

## Shipped in every build

### Resting heart rate: CDC / NCHS
- **Source:** Ostchega Y, Porter KS, Hughes J, Dillon CF, Nwankwo T. *Resting
  Pulse Rate Reference Data for Children, Adolescents, and Adults: United States,
  1999–2008.* National Health Statistics Reports No. 41. NCHS, 24 August 2011.
  <https://www.cdc.gov/nchs/data/nhsr/nhsr041.pdf>
- **Licence:** US government work. The report says it is "in the public domain
  and may be reproduced".
- **Data used:** Tables 2 (males) and 3 (females): the 5th, 10th, 25th, 50th, 75th,
  90th and 95th percentiles for age bands 16–19, 20–39, 40–59, 60–79 and 80+.
- **Caveats shown in the app:**
  - The survey measured *seated pulse after about 4 minutes of rest*. Apple Watch
    estimates resting heart rate differently, usually lower.
  - It's US data from 1999–2008, excluding people with conditions or medication
    affecting pulse.

### Sleep duration: AASM and SRS consensus
- **Source:** Watson NF, Badr MS, Belenky G, et al. *Recommended Amount of Sleep
  for a Healthy Adult: A Joint Consensus Statement of the American Academy of Sleep
  Medicine and Sleep Research Society.* J Clin Sleep Med. 2015;11(6):591–592.
  doi:10.5664/jcsm.4758
- **Data used:** the recommendation of 7 hours or more for adults aged 18–60. This
  is a published recommendation, quoted and attributed. No table is reproduced.
- **Not used:** the National Sleep Foundation's 2015 ranges (Hirshkowitz et al.,
  *Sleep Health*). I couldn't confirm the exact age bands from the primary source,
  so people over 60 see a note that the AASM/SRS statement covers ages 18–60.

## VO2 max (decision 10)

- **Every build:** no reference table. Metric detail points to Apple Health, which
  already shows each person's Cardio Fitness level by age and sex, using FRIEND
  data (Apple Newsroom, December 2020).
- **The owner's non-commercial build only** (`VIVRA_NONCOMMERCIAL` compilation
  condition, off by default):
  - **Data:** FRIEND treadmill medians (50th percentile) by sex and decade, from
    Kaminsky LA, Arena R, Myers J. *Reference Standards for Cardiorespiratory Fitness
    Measured With Cardiopulmonary Exercise Testing: Data From the Fitness Registry and
    the Importance of Exercise National Database.* Mayo Clin Proc. 2015;90(11):1515–1523.
    doi:10.1016/j.mayocp.2015.07.026 (Table 3). These were taken from the author
    manuscript in PubMed Central (PMC4919021).
  - **Why non-commercial only:** the 2022 update (Mayo Clin Proc 2022;97(2):285–293)
    is CC BY-NC-ND. The 2015 paper is copyrighted with no open licence. Commercial
    products that show these comparisons license the data: Garmin uses The Cooper
    Institute's tables "with permission".
  - **Caveats shown in the app:** these are lab treadmill tests from 2014–2015 in the
    US, and Apple Watch estimates VO2 max from outdoor walks and runs, so values
    aren't directly comparable. The 2022 update reports treadmill values 1.5–4.6
    mL/kg/min lower than 2015.
  - **Distribution:** the data is compiled only into builds with the flag. CI builds
    both to make sure the flagged code compiles, and only the default build is
    tested and shipped.

## Rules for adding a norm

1. Check the licence on the primary source, and record it here.
2. Copy the values from the primary source (not a blog or calculator), and note
   the table.
3. Show the citation and the caveats wherever the comparison appears.
4. Use neutral wording only: "between the 25th and 50th percentiles". Never use
   category labels like "poor" or "excellent" (they're banned terms anyway).
