# Research notes: register and sign-off

Research notes are short summaries of published studies about **groups of people**,
shown word for word beside a pattern in Vivra's summaries (PLAN decision 11). People
write and review them; the model never writes about research, and Swift, not the
model, picks which card goes with which pattern. This is the sister document to
`docs/NORMS.md`, and the writing rules are in `docs/STYLE_GUIDE.md` (Research notes).

The cards live in `Packages/VivraCore/Sources/Evidence/BundledEvidence.swift`
(version `2026.11`). `EvidenceCardLintTests` checks every shown card against the
writing rules, and that every check the insight engine makes has a card.

## How a card ships

Every card below is a **draft**. Release builds show only `ready` cards, so until you
sign cards off, Release builds show no research notes. Debug builds (what Xcode runs
on your iPhone) also show drafts, labelled "Draft, not yet reviewed", so you can see
each one in place.

How the drafts were made (Phase 8):

1. One question per engine check and per metric's background: "What did studies find
   about X and Y, in whom, and how strong is it?"
2. Systematic reviews and meta-analyses first, then large cohorts, then trials,
   preferring the last ten years. Primary sources only.
3. Every citation (authors, title, journal, year, volume, pages, DOI, licence) was
   checked against Crossref and PubMed. Every statement was checked against at least
   the abstract, and against the full text where it's open (marked below).
4. Statements were written in our own words with AI help at a desk, never on device,
   and nothing was quoted. Facts aren't copyrightable, but the licence of each source
   is recorded anyway.

**To sign a card off** (you, optionally with a qualified reviewer such as a sleep or
exercise physiologist):

- [ ] Read the source, ideally the full text, and check the statement says what it
  found, in whom, and in the right direction.
- [ ] Check the population, the caveats and the strength label are fair.
- [ ] Check the card matches the right engine check, and that "indirect" cards say
  what was measured.
- [ ] In `BundledEvidence.swift`, set `status: .ready`, `reviewedOn` to today and
  `reviewers` to your initials, and bump `BundledEvidence.version`. Tick the card in
  the table below.

Change a card's wording or sources only by raising its `revision`. Withdraw a card by
setting it to `excluded`, never by deleting it: saved summaries then say "This
research note has since been withdrawn."

**Cadence:** review every card at least every 12 months, and before each release
check its sources for retractions (PubMed's retraction notice, Retraction Watch) and
for newer meta-analyses.

## Register

| Card | Matches | Shown in | Strength | Status | Sources (licence; checked against) | Owner sign-off |
|---|---|---|---|---|---|---|
| `alcohol.sleepDuration.nextNight` | alcohol→sleepDuration, lag 1 | Pattern notes | moderate | draft | Gardiner et al. 2025 ([doi:10.1016/j.smrv.2024.102030](https://doi.org/10.1016/j.smrv.2024.102030)); © Elsevier; nothing copied; checked: abstract | ☐ |
| `alcohol.hrv.nextNight` | alcohol→heartRateVariability, lag 1 | Pattern notes | moderate | draft | Pietilä et al. 2018 ([doi:10.2196/mental.9519](https://doi.org/10.2196/mental.9519)); CC BY 4.0; checked: full text | ☐ |
| `alcohol.restingHeartRate.nextNight` | alcohol→restingHeartRate, lag 1 | Pattern notes | moderate | draft | Pietilä et al. 2018 ([doi:10.2196/mental.9519](https://doi.org/10.2196/mental.9519)); CC BY 4.0; checked: full text | ☐ |
| `caffeine.sleepDuration.nextNight` | caffeine→sleepDuration, lag 1 | Pattern notes | consistent | draft | Gardiner et al. 2023 ([doi:10.1016/j.smrv.2023.101764](https://doi.org/10.1016/j.smrv.2023.101764)); © Elsevier; nothing copied; checked: abstract | ☐ |
| `workoutDay.sleepDuration` | group: workoutDay→sleepDuration | Pattern notes | consistent | draft | Kredlow et al. 2015 ([doi:10.1007/s10865-015-9617-6](https://doi.org/10.1007/s10865-015-9617-6)); © Springer; nothing copied; checked: abstract | ☐ |
| `steps.sleepDuration.nextNight` | steps→sleepDuration, lag 1 | Pattern notes | moderate | draft | Atoui et al. 2021 ([doi:10.1016/j.smrv.2021.101426](https://doi.org/10.1016/j.smrv.2021.101426)); © Elsevier; nothing copied; checked: abstract | ☐ |
| `exercise.hrv.nextDay` | exerciseMinutes→heartRateVariability, lag 1 | Pattern notes | moderate | draft | Stanley et al. 2013 ([doi:10.1007/s40279-013-0083-4](https://doi.org/10.1007/s40279-013-0083-4)); © Springer; nothing copied; checked: abstract | ☐ |
| `sleep.mood.experiments` | sleepDuration→mood, lag 0 | Pattern notes | consistent | draft | Tomaso et al. 2021 ([doi:10.1093/sleep/zsaa289](https://doi.org/10.1093/sleep/zsaa289)); © Oxford University Press; nothing copied; checked: abstract<br>Palmer et al. 2024 ([doi:10.1037/bul0000410](https://doi.org/10.1037/bul0000410)); © American Psychological Association; nothing copied; checked: abstract | ☐ |
| `sleep.mood.daily` | sleepDuration→mood, lag 0 | Pattern notes | moderate | draft | Hickman et al. 2024 ([doi:10.3390/s24144701](https://doi.org/10.3390/s24144701)); CC BY 4.0; checked: abstract | ☐ |
| `sleep.energy.nextDay` | sleepDuration→energyLevel, lag 0 | Pattern notes | consistent | draft | Wüst et al. 2024 ([doi:10.1016/j.smrv.2024.101940](https://doi.org/10.1016/j.smrv.2024.101940)); © Elsevier; nothing copied; checked: abstract | ☐ |
| `sleep.stress.nextDay` | sleepDuration→stressLevel, lag 0 | Pattern notes | consistent | draft | Palmer et al. 2024 ([doi:10.1037/bul0000410](https://doi.org/10.1037/bul0000410)); © American Psychological Association; nothing copied; checked: abstract | ☐ |
| `sleep.hrv.nextDay` | sleepDuration→heartRateVariability, lag 0 | Pattern notes | moderate | draft | Zhang et al. 2025 ([doi:10.3389/fneur.2025.1556784](https://doi.org/10.3389/fneur.2025.1556784)); CC BY 4.0; checked: abstract | ☐ |
| `mindfulness.stress` | mindfulMinutes→stressLevel, lag 0 | Pattern notes | moderate | draft | Khoury et al. 2015 ([doi:10.1016/j.jpsychores.2015.03.009](https://doi.org/10.1016/j.jpsychores.2015.03.009)); © Elsevier; nothing copied; checked: abstract | ☐ |
| `mindfulness.sleep` | mindfulMinutes→sleepDuration, lag 1 | Pattern notes | moderate | draft | Rusch et al. 2019 ([doi:10.1111/nyas.13996](https://doi.org/10.1111/nyas.13996)); © Wiley; nothing copied; checked: abstract | ☐ |
| `stress.sleep.nextNight` | stressLevel→sleepDuration, lag 1 | Pattern notes | limited | draft | Åkerstedt et al. 2012 ([doi:10.1016/j.sleep.2011.12.013](https://doi.org/10.1016/j.sleep.2011.12.013)); © Elsevier; nothing copied; checked: abstract | ☐ |
| `activity.mood.sameDay` | steps→mood, lag 0, exerciseMinutes→mood, lag 0 | Pattern notes | moderate | draft | Liao et al. 2015 ([doi:10.3389/fpsyg.2015.01975](https://doi.org/10.3389/fpsyg.2015.01975)); CC BY 4.0; checked: abstract | ☐ |
| `caffeine.timing` | context: caffeine | Metric detail | limited | draft | Drake et al. 2013 ([doi:10.5664/jcsm.3170](https://doi.org/10.5664/jcsm.3170)); © American Academy of Sleep Medicine; nothing copied; checked: abstract | ☐ |
| `exercise.evening.sleep` | context: workoutMinutes | Metric detail | moderate | draft | Stutz et al. 2019 ([doi:10.1007/s40279-018-1015-0](https://doi.org/10.1007/s40279-018-1015-0)); © Springer; nothing copied; checked: abstract | ☐ |
| `restingHeartRate.withinPerson` | context: restingHeartRate | Metric detail | moderate | draft | Quer et al. 2020 ([doi:10.1371/journal.pone.0227709](https://doi.org/10.1371/journal.pone.0227709)); CC BY 4.0; checked: full text | ☐ |
| `hrv.dayToDay` | context: heartRateVariability | Metric detail | moderate | draft | Buchheit 2014 ([doi:10.3389/fphys.2014.00073](https://doi.org/10.3389/fphys.2014.00073)); CC BY 4.0; checked: abstract | ☐ |
| `hrv.measurement` | context: heartRateVariability | Metric detail | consistent | draft | Shaffer et al. 2017 ([doi:10.3389/fpubh.2017.00258](https://doi.org/10.3389/fpubh.2017.00258)); CC BY 4.0; checked: abstract | ☐ |
| `sleep.tracking` | context: sleepDuration | Metric detail | limited | draft | Miller et al. 2022 ([doi:10.3390/s22166317](https://doi.org/10.3390/s22166317)); CC BY 4.0; checked: abstract | ☐ |
| `mindfulness.hrv` | context: mindfulMinutes | Metric detail | mixed | draft | Brown et al. 2021 ([doi:10.1097/PSY.0000000000000900](https://doi.org/10.1097/PSY.0000000000000900)); © Wolters Kluwer; nothing copied; checked: abstract | ☐ |
| `shorterSleep.restingHeartRate.betweenPeople` | group: shorterSleep→restingHeartRate | Never | moderate | referenceOnly | Quer et al. 2020 ([doi:10.1371/journal.pone.0227709](https://doi.org/10.1371/journal.pone.0227709)); CC BY 4.0; checked: full text | — |
| `alcohol.remSleep` | — | Never | consistent | referenceOnly | Gardiner et al. 2025 ([doi:10.1016/j.smrv.2024.102030](https://doi.org/10.1016/j.smrv.2024.102030)); © Elsevier; nothing copied; checked: abstract | — |

"Pattern notes" cards appear under a matching pattern of medium or high confidence in
the daily check-in, weekly and monthly summaries (at most three per summary), and in
the pattern's detail in Connections. "Metric detail" cards appear under "What Research
Says" on a metric's detail screen. "Never" cards are kept for the record.

## Excluded or held

| Card | Decision | Why |
|---|---|---|
| `steps.depression` | Excluded (owner, Phase 8) | A clinical condition; every honest wording needs words the style guide bans, and it would read as advice. Source considered: Bizzozero-Peroni B, et al. *JAMA Netw Open.* 2024;7(12):e2451208. |
| `illness.signals` | Excluded (owner, Phase 8) | Illness detection from heart rate, breathing or temperature is diagnosis, which Vivra never does. Sources considered: Radin JM, et al. *Lancet Digit Health.* 2020; Miller DJ, et al. *PLoS One.* 2020. |
| `wristTemperature.cycle` | Held until the owner decides | Reproductive health is sensitive. Sources considered: Maijala A, et al. *BMC Womens Health.* 2019; Wang Z, et al. *Hum Reprod.* 2025 (CC BY-NC). |
| `shorterSleep.restingHeartRate.betweenPeople` | Kept for the record | Compares people, not one person's nights, so it isn't shown under a personal pattern. |
| `alcohol.remSleep` | Kept for the record | Vivra has no REM sleep metric yet (separate work). |

Topics for later, with no metric yet: sleep regularity and mood (Fang Y, et al. *npj
Digit Med.* 2021;4:28, CC BY) and late eating and sleep (Bohlman C, et al. *Front
Nutr.* 2024;11:1419811, CC BY).

## Owner read-through

Twenty sentence-and-note pairs, as the template summaries would show them (from the
eval corpus, drafts included). Read each pair together and tick it when the note reads
as what studies found in groups of people, and not as the reason for the sentence
above it. Note any pair that doesn't.

1. **sleep.energy.nextDay** (seed1-weekly)
   - Sentence: After a night of 7h 37m or more, your energy level had a median of 4 out of 5, compared with 2 out of 5 after a night of 7h 6m or less (75 days compared, high confidence).
   - Note: Across experiments, after a single night with sleep cut to a few hours, people rated themselves as sleepier. These studies measured sleepiness, not the energy level Vivra logs.
   - ☐ Reads as groups of people, not a reason for this person's data
2. **sleep.hrv.nextDay** (seed1-weekly)
   - Sentence: After a night of 7h 34m or more, your heart rate variability (SDNN) had a median of 56 ms, compared with 44 ms after a night of 7h 5m or less (89 days compared, high confidence).
   - Note: Across trials in which people went without sleep, one measure of heart rate variability, RMSSD, was lower afterwards. SDNN, the measure Apple Watch reports, didn't differ clearly.
   - ☐ Reads as groups of people, not a reason for this person's data
3. **sleep.mood.experiments** (seed1-weekly)
   - Sentence: After a night of 7h 37m or more, your mood had a median of 4 out of 5, compared with 3 out of 5 after a night of 7h 6m or less (75 days compared, high confidence).
   - Note: Across experiments in which people's sleep was cut short, they reported less positive mood afterwards, and somewhat more negative mood.
   - ☐ Reads as groups of people, not a reason for this person's data
4. **caffeine.sleepDuration.nextNight** (hand-daily-mixed)
   - Sentence: On days with 190 mg or more of caffeine, you slept a median of 6h 36m the following night, compared with 7h 24m on days with 95 mg or less of caffeine (84 days compared, high confidence).
   - Note: Across controlled studies of adults, caffeine was followed by shorter sleep, more time to fall asleep and less deep sleep. The differences were larger when caffeine was taken closer to bedtime.
   - ☐ Reads as groups of people, not a reason for this person's data
5. **alcohol.hrv.nextNight** (hand-weekly-single-pattern)
   - Sentence: On days with any alcohol, your heart rate variability (SDNN) the next day had a median of 43 ms, compared with 51 ms on days with no alcohol (88 days compared, medium confidence).
   - Note: In a large study of Finnish employees, each person's heart rate variability during the first hours of sleep was lower on nights after drinking than on nights without, and more so after more drinks.
   - ☐ Reads as groups of people, not a reason for this person's data
6. **workoutDay.sleepDuration** (hand-monthly-full)
   - Sentence: On nights after a day with at least 20 minutes of workouts, you slept a median of 7h 30m, compared with 7h 0m after days without a workout (30 and 52 nights compared, medium confidence).
   - Note: Across studies of adults, sleep was slightly longer after single exercise sessions and with regular exercise, and regular exercise went with higher ratings of sleep quality. The differences in sleep time were small.
   - ☐ Reads as groups of people, not a reason for this person's data
7. **alcohol.sleepDuration.nextNight** (research-mixed)
   - Sentence: On days with 2 drinks or more of alcohol, you slept a median of 6h 42m the following night, compared with 7h 12m on days with 1 drink or less of alcohol (72 days compared, medium confidence).
   - Note: In lab studies of adults without sleep problems, total sleep after evening alcohol varied between studies, with no clear overall difference. The clearer finding was less REM sleep, starting from about two standard drinks.
   - ☐ Reads as groups of people, not a reason for this person's data
8. **steps.sleepDuration.nextNight** (research-mixed)
   - Sentence: On days with 2 steps or more, you slept a median of 7h 0m the following night, compared with 7h 18m on days with 1 steps or less (72 days compared, medium confidence).
   - Note: In studies that followed adults day by day, more active days weren't consistently followed by longer sleep that night. The links that were found were small and varied between studies.
   - ☐ Reads as groups of people, not a reason for this person's data
9. **mindfulness.sleep** (research-indirect)
   - Sentence: On days with 2 min or more of mindfulness, you slept a median of 7h 18m the following night, compared with 6h 54m on days with 1 min or less of mindfulness (72 days compared, medium confidence).
   - Note: In trials, people who learned mindfulness meditation rated their sleep quality higher than people in some comparison groups. These trials measured how people rated their sleep, not how long they slept.
   - ☐ Reads as groups of people, not a reason for this person's data
10. **sleep.energy.nextDay** (seed2-daily)
   - Sentence: After a night of 7h 37m or more, your energy level had a median of 4 out of 5, compared with 3 out of 5 after a night of 7h 4m or less (76 days compared, high confidence).
   - Note: Across experiments, after a single night with sleep cut to a few hours, people rated themselves as sleepier. These studies measured sleepiness, not the energy level Vivra logs.
   - ☐ Reads as groups of people, not a reason for this person's data
11. **sleep.hrv.nextDay** (seed2-weekly)
   - Sentence: After a night of 7h 38m or more, your heart rate variability (SDNN) had a median of 57 ms, compared with 43 ms after a night of 7h 2m or less (89 days compared, high confidence).
   - Note: Across trials in which people went without sleep, one measure of heart rate variability, RMSSD, was lower afterwards. SDNN, the measure Apple Watch reports, didn't differ clearly.
   - ☐ Reads as groups of people, not a reason for this person's data
12. **sleep.mood.experiments** (seed2-weekly)
   - Sentence: After a night of 7h 37m or more, your mood had a median of 4 out of 5, compared with 3 out of 5 after a night of 7h 4m or less (76 days compared, high confidence).
   - Note: Across experiments in which people's sleep was cut short, they reported less positive mood afterwards, and somewhat more negative mood.
   - ☐ Reads as groups of people, not a reason for this person's data
13. **caffeine.sleepDuration.nextNight** (research-cap)
   - Sentence: On days with 2 mg or more of caffeine, you slept a median of 6h 48m the following night, compared with 7h 24m on days with 1 mg or less of caffeine (72 days compared, medium confidence).
   - Note: Across controlled studies of adults, caffeine was followed by shorter sleep, more time to fall asleep and less deep sleep. The differences were larger when caffeine was taken closer to bedtime.
   - ☐ Reads as groups of people, not a reason for this person's data
14. **alcohol.hrv.nextNight** (research-agrees)
   - Sentence: On days with 2 drinks or more of alcohol, your heart rate variability (SDNN) the next day had a median of 43 ms, compared with 51 ms on days with 1 drink or less of alcohol (72 days compared, medium confidence).
   - Note: In a large study of Finnish employees, each person's heart rate variability during the first hours of sleep was lower on nights after drinking than on nights without, and more so after more drinks.
   - ☐ Reads as groups of people, not a reason for this person's data
15. **sleep.energy.nextDay** (seed3-weekly)
   - Sentence: After a night of 7h 40m or more, your energy level had a median of 3.5 out of 5, compared with 3 out of 5 after a night of 6h 57m or less (76 days compared, high confidence).
   - Note: Across experiments, after a single night with sleep cut to a few hours, people rated themselves as sleepier. These studies measured sleepiness, not the energy level Vivra logs.
   - ☐ Reads as groups of people, not a reason for this person's data
16. **sleep.hrv.nextDay** (seed3-weekly)
   - Sentence: After a night of 7h 40m or more, your heart rate variability (SDNN) had a median of 58 ms, compared with 47 ms after a night of 6h 58m or less (89 days compared, high confidence).
   - Note: Across trials in which people went without sleep, one measure of heart rate variability, RMSSD, was lower afterwards. SDNN, the measure Apple Watch reports, didn't differ clearly.
   - ☐ Reads as groups of people, not a reason for this person's data
17. **sleep.mood.experiments** (seed3-weekly)
   - Sentence: After a night of 7h 40m or more, your mood had a median of 4 out of 5, compared with 3 out of 5 after a night of 6h 57m or less (76 days compared, high confidence).
   - Note: Across experiments in which people's sleep was cut short, they reported less positive mood afterwards, and somewhat more negative mood.
   - ☐ Reads as groups of people, not a reason for this person's data
18. **sleep.energy.nextDay** (seed4-daily)
   - Sentence: After a night of 7h 25m or more, your energy level had a median of 4 out of 5, compared with 2.5 out of 5 after a night of 6h 50m or less (76 days compared, high confidence).
   - Note: Across experiments, after a single night with sleep cut to a few hours, people rated themselves as sleepier. These studies measured sleepiness, not the energy level Vivra logs.
   - ☐ Reads as groups of people, not a reason for this person's data
19. **sleep.hrv.nextDay** (seed4-weekly)
   - Sentence: After a night of 7h 25m or more, your heart rate variability (SDNN) had a median of 54 ms, compared with 43 ms after a night of 6h 50m or less (89 days compared, high confidence).
   - Note: Across trials in which people went without sleep, one measure of heart rate variability, RMSSD, was lower afterwards. SDNN, the measure Apple Watch reports, didn't differ clearly.
   - ☐ Reads as groups of people, not a reason for this person's data
20. **sleep.mood.experiments** (seed4-weekly)
   - Sentence: After a night of 7h 25m or more, your mood had a median of 4 out of 5, compared with 3 out of 5 after a night of 6h 50m or less (76 days compared, high confidence).
   - Note: Across experiments in which people's sleep was cut short, they reported less positive mood afterwards, and somewhat more negative mood.
   - ☐ Reads as groups of people, not a reason for this person's data
