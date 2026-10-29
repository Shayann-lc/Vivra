import InsightEngine
import VivraModel

/// The research notes shipped in the app (PLAN decision 11). Written by
/// people in our own words, each checked against its sources; the register,
/// licences and sign-off checklist are in `docs/EVIDENCE.md`. A card is shown
/// in Release builds only once its status is `ready`.
///
/// Change a card's wording or sources only by raising its `revision`.
/// Withdraw a card by setting it to `excluded`, never by deleting it, so saved
/// reports can say it was withdrawn.
public enum BundledEvidence {
    /// Bump whenever any card changes.
    public static let version = "2026.11"

    public static let cards: [EvidenceCard] = patternCards + contextCards + recordOnlyCards

    // MARK: Sources

    static let pietila2018 = EvidenceSource(
        authors: "Pietilä J, Helander E, Korhonen I, Myllymäki T, Kujala UM, Lindholm H.",
        title:
            "Acute effect of alcohol intake on cardiovascular autonomic regulation during the first hours of sleep "
            + "in a large real-world sample of Finnish employees: observational study",
        journal: "JMIR Ment Health",
        year: 2018,
        volumeAndPages: "5(1):e23",
        doi: "10.2196/mental.9519",
        url: "https://doi.org/10.2196/mental.9519",
        design:
            "Observational, each person compared with themselves; 4,098 employees in Finland; heart rate and HRV "
            + "(RMSSD) recorded during the first 3 hours of sleep",
        licence: "CC BY 4.0",
        checked: .fullText
    )

    static let gardinerAlcohol2025 = EvidenceSource(
        authors: "Gardiner C, Weakley J, Burke LM, Roach GD, Sargent C, Maniar N, et al.",
        title: "The effect of alcohol on subsequent sleep in healthy adults: a systematic review and meta-analysis",
        journal: "Sleep Med Rev",
        year: 2025,
        volumeAndPages: "80:102030",
        doi: "10.1016/j.smrv.2024.102030",
        url: "https://doi.org/10.1016/j.smrv.2024.102030",
        design: "Systematic review and meta-analysis of 27 laboratory studies of healthy adults",
        licence: "© Elsevier; nothing copied",
        checked: .abstract
    )

    static let gardinerCaffeine2023 = EvidenceSource(
        authors: "Gardiner C, Weakley J, Burke LM, Roach GD, Sargent C, Maniar N, et al.",
        title: "The effect of caffeine on subsequent sleep: a systematic review and meta-analysis",
        journal: "Sleep Med Rev",
        year: 2023,
        volumeAndPages: "69:101764",
        doi: "10.1016/j.smrv.2023.101764",
        url: "https://doi.org/10.1016/j.smrv.2023.101764",
        design: "Systematic review and meta-analysis of 24 studies",
        licence: "© Elsevier; nothing copied",
        checked: .abstract
    )

    static let drake2013 = EvidenceSource(
        authors: "Drake C, Roehrs T, Shambroom J, Roth T.",
        title: "Caffeine effects on sleep taken 0, 3, or 6 hours before going to bed",
        journal: "J Clin Sleep Med",
        year: 2013,
        volumeAndPages: "9(11):1195–1200",
        doi: "10.5664/jcsm.3170",
        url: "https://doi.org/10.5664/jcsm.3170",
        design: "Randomised crossover study; 12 adults; 400 mg caffeine; sleep measured at home with a monitor",
        licence: "© American Academy of Sleep Medicine; nothing copied",
        checked: .abstract
    )

    static let stutz2019 = EvidenceSource(
        authors: "Stutz J, Eiholzer R, Spengler CM.",
        title: "Effects of evening exercise on sleep in healthy participants: a systematic review and meta-analysis",
        journal: "Sports Med",
        year: 2019,
        volumeAndPages: "49(2):269–287",
        doi: "10.1007/s40279-018-1015-0",
        url: "https://doi.org/10.1007/s40279-018-1015-0",
        design: "Systematic review and meta-analysis of 23 studies of single evening exercise sessions",
        licence: "© Springer; nothing copied",
        checked: .abstract
    )

    static let kredlow2015 = EvidenceSource(
        authors: "Kredlow MA, Capozzoli MC, Hearon BA, Calkins AW, Otto MW.",
        title: "The effects of physical activity on sleep: a meta-analytic review",
        journal: "J Behav Med",
        year: 2015,
        volumeAndPages: "38(3):427–449",
        doi: "10.1007/s10865-015-9617-6",
        url: "https://doi.org/10.1007/s10865-015-9617-6",
        design: "Meta-analysis of 66 studies of single sessions and regular exercise",
        licence: "© Springer; nothing copied",
        checked: .abstract
    )

    static let atoui2021 = EvidenceSource(
        authors: "Atoui S, Chevance G, Romain AJ, Kingsbury C, Lachance JP, Bernard P.",
        title: "Daily associations between sleep and physical activity: a systematic review and meta-analysis",
        journal: "Sleep Med Rev",
        year: 2021,
        volumeAndPages: "57:101426",
        doi: "10.1016/j.smrv.2021.101426",
        url: "https://doi.org/10.1016/j.smrv.2021.101426",
        design: "Systematic review and meta-analysis of 33 studies that followed adults day by day",
        licence: "© Elsevier; nothing copied",
        checked: .abstract
    )

    static let stanley2013 = EvidenceSource(
        authors: "Stanley J, Peake JM, Buchheit M.",
        title: "Cardiac parasympathetic reactivation following exercise: implications for training prescription",
        journal: "Sports Med",
        year: 2013,
        volumeAndPages: "43(12):1259–1277",
        doi: "10.1007/s40279-013-0083-4",
        url: "https://doi.org/10.1007/s40279-013-0083-4",
        design: "Review with a quantitative analysis of studies of aerobic exercise in athletes and healthy adults",
        licence: "© Springer; nothing copied",
        checked: .abstract
    )

    static let tomaso2021 = EvidenceSource(
        authors: "Tomaso CC, Johnson AB, Nelson TD.",
        title:
            "The effect of sleep deprivation and restriction on mood, emotion, and emotion regulation: three "
            + "meta-analyses in one",
        journal: "Sleep",
        year: 2021,
        volumeAndPages: "44(6):zsaa289",
        doi: "10.1093/sleep/zsaa289",
        url: "https://doi.org/10.1093/sleep/zsaa289",
        design: "Three meta-analyses; 64 studies",
        licence: "© Oxford University Press; nothing copied",
        checked: .abstract
    )

    static let palmer2024 = EvidenceSource(
        authors: "Palmer CA, Bower JL, Cho KW, Clementi MA, Lau S, Oosterhoff B, Alfano CA.",
        title:
            "Sleep loss and emotion: a systematic review and meta-analysis of over 50 years of experimental "
            + "research",
        journal: "Psychol Bull",
        year: 2024,
        volumeAndPages: "150(4):440–463",
        doi: "10.1037/bul0000410",
        url: "https://doi.org/10.1037/bul0000410",
        design: "Systematic review and meta-analysis of 154 experiments; 5,717 people",
        licence: "© American Psychological Association; nothing copied",
        checked: .abstract
    )

    static let hickman2024 = EvidenceSource(
        authors: "Hickman R, D'Oliveira TC, Davies A, Shergill S.",
        title: "Monitoring daily sleep, mood, and affect using digital technologies and wearables: a systematic review",
        journal: "Sensors (Basel)",
        year: 2024,
        volumeAndPages: "24(14):4701",
        doi: "10.3390/s24144701",
        url: "https://doi.org/10.3390/s24144701",
        design: "Systematic review of 121 studies that followed people day by day",
        licence: "CC BY 4.0",
        checked: .abstract
    )

    static let wust2024 = EvidenceSource(
        authors: "Wüst LN, Capdevila NC, Lane LT, Reichert CF, Lasauskaite R.",
        title:
            "Impact of one night of sleep restriction on sleepiness and cognitive function: a systematic review and "
            + "meta-analysis",
        journal: "Sleep Med Rev",
        year: 2024,
        volumeAndPages: "76:101940",
        doi: "10.1016/j.smrv.2024.101940",
        url: "https://doi.org/10.1016/j.smrv.2024.101940",
        design: "Systematic review and meta-analysis of 44 studies; sleep cut to 2–6 hours for one night",
        licence: "© Elsevier; nothing copied",
        checked: .abstract
    )

    static let zhang2025 = EvidenceSource(
        authors: "Zhang S, Niu X, Ma J, Wei X, Zhang J, Du W.",
        title: "Effects of sleep deprivation on heart rate variability: a systematic review and meta-analysis",
        journal: "Front Neurol",
        year: 2025,
        volumeAndPages: "16:1556784",
        doi: "10.3389/fneur.2025.1556784",
        url: "https://doi.org/10.3389/fneur.2025.1556784",
        design: "Systematic review and meta-analysis of 11 randomised trials; 549 people",
        licence: "CC BY 4.0",
        checked: .abstract
    )

    static let khoury2015 = EvidenceSource(
        authors: "Khoury B, Sharma M, Rush SE, Fournier C.",
        title: "Mindfulness-based stress reduction for healthy individuals: a meta-analysis",
        journal: "J Psychosom Res",
        year: 2015,
        volumeAndPages: "78(6):519–528",
        doi: "10.1016/j.jpsychores.2015.03.009",
        url: "https://doi.org/10.1016/j.jpsychores.2015.03.009",
        design: "Meta-analysis of 29 studies; 2,668 adults",
        licence: "© Elsevier; nothing copied",
        checked: .abstract
    )

    static let rusch2019 = EvidenceSource(
        authors: "Rusch HL, Rosario M, Levison LM, Olivera A, Livingston WS, Wu T, et al.",
        title:
            "The effect of mindfulness meditation on sleep quality: a systematic review and meta-analysis of "
            + "randomized controlled trials",
        journal: "Ann N Y Acad Sci",
        year: 2019,
        volumeAndPages: "1445(1):5–16",
        doi: "10.1111/nyas.13996",
        url: "https://doi.org/10.1111/nyas.13996",
        design: "Meta-analysis of 18 randomised trials; 1,654 people",
        licence: "© Wiley; nothing copied",
        checked: .abstract
    )

    static let akerstedt2012 = EvidenceSource(
        authors: "Åkerstedt T, Orsini N, Petersen H, Axelsson J, Lekander M, Kecklund G.",
        title:
            "Predicting sleep quality from stress and prior sleep: a study of day-to-day covariation across six weeks",
        journal: "Sleep Med",
        year: 2012,
        volumeAndPages: "13(6):674–679",
        doi: "10.1016/j.sleep.2011.12.013",
        url: "https://doi.org/10.1016/j.sleep.2011.12.013",
        design: "Diary study; 50 people; 42 days",
        licence: "© Elsevier; nothing copied",
        checked: .abstract
    )

    static let liao2015 = EvidenceSource(
        authors: "Liao Y, Shonkoff ET, Dunton GF.",
        title:
            "The acute relationships between affect, physical feeling states, and physical activity in daily life: "
            + "a review of current evidence",
        journal: "Front Psychol",
        year: 2015,
        volumeAndPages: "6:1975",
        doi: "10.3389/fpsyg.2015.01975",
        url: "https://doi.org/10.3389/fpsyg.2015.01975",
        design: "Systematic review of 14 studies in everyday life",
        licence: "CC BY 4.0",
        checked: .abstract
    )

    static let quer2020 = EvidenceSource(
        authors: "Quer G, Gouda P, Galarnyk M, Topol EJ, Steinhubl SR.",
        title:
            "Inter- and intraindividual variability in daily resting heart rate and its associations with age, sex, "
            + "sleep, BMI, and time of year: retrospective, longitudinal cohort study of 92,457 adults",
        journal: "PLoS One",
        year: 2020,
        volumeAndPages: "15(2):e0227709",
        doi: "10.1371/journal.pone.0227709",
        url: "https://doi.org/10.1371/journal.pone.0227709",
        design: "Retrospective cohort; 92,457 US adults with wrist trackers; a median of 320 days each",
        licence: "CC BY 4.0",
        checked: .fullText
    )

    static let buchheit2014 = EvidenceSource(
        authors: "Buchheit M.",
        title: "Monitoring training status with HR measures: do all roads lead to Rome?",
        journal: "Front Physiol",
        year: 2014,
        volumeAndPages: "5:73",
        doi: "10.3389/fphys.2014.00073",
        url: "https://doi.org/10.3389/fphys.2014.00073",
        design: "Review of heart rate monitoring in athletes",
        licence: "CC BY 4.0",
        checked: .abstract
    )

    static let shaffer2017 = EvidenceSource(
        authors: "Shaffer F, Ginsberg JP.",
        title: "An overview of heart rate variability metrics and norms",
        journal: "Front Public Health",
        year: 2017,
        volumeAndPages: "5:258",
        doi: "10.3389/fpubh.2017.00258",
        url: "https://doi.org/10.3389/fpubh.2017.00258",
        design: "Methods review",
        licence: "CC BY 4.0",
        checked: .abstract
    )

    static let miller2022 = EvidenceSource(
        authors: "Miller DJ, Sargent C, Roach GD.",
        title:
            "A validation of six wearable devices for estimating sleep, heart rate and heart rate variability in "
            + "healthy adults",
        journal: "Sensors (Basel)",
        year: 2022,
        volumeAndPages: "22(16):6317",
        doi: "10.3390/s22166317",
        url: "https://doi.org/10.3390/s22166317",
        design: "Laboratory validation; 53 adults; one night; compared with polysomnography",
        licence: "CC BY 4.0",
        checked: .abstract
    )

    static let brown2021 = EvidenceSource(
        authors: "Brown L, Rando AA, Eichel K, Van Dam NT, Celano CM, Huffman JC, Morris ME.",
        title:
            "The effects of mindfulness and meditation on vagally mediated heart rate variability: a meta-analysis",
        journal: "Psychosom Med",
        year: 2021,
        volumeAndPages: "83(6):631–640",
        doi: "10.1097/PSY.0000000000000900",
        url: "https://doi.org/10.1097/PSY.0000000000000900",
        design: "Meta-analysis of 19 randomised trials",
        licence: "© Wolters Kluwer; nothing copied",
        checked: .abstract
    )

    // MARK: Cards shown under patterns

    static let groupsCaveat = "Results describe groups of people and may not match any one person."

    static let patternCards: [EvidenceCard] = [
        EvidenceCard(
            id: "alcohol.sleepDuration.nextNight",
            matches: [.correlation(x: .alcohol, y: .sleepDuration, lag: 1)],
            direction: .mixed,
            statement:
                "In lab studies of adults without sleep problems, total sleep after evening alcohol varied between studies, with no "
                + "clear overall difference. The clearer finding was less REM sleep, starting from about two "
                + "standard drinks.",
            population: "Adults without sleep problems, mostly young, sleeping in a laboratory",
            caveats: [
                "Alcohol was given in set amounts at set times.",
                "A standard drink differs from country to country.",
                "Apple Watch estimates sleep stages; the studies measured them with brain recordings.",
                groupsCaveat,
            ],
            strength: .moderate,
            sources: [gardinerAlcohol2025],
            surfaces: [.patternNote]
        ),
        EvidenceCard(
            id: "alcohol.hrv.nextNight",
            matches: [.correlation(x: .alcohol, y: .heartRateVariability, lag: 1)],
            direction: .lower,
            statement:
                "In a large study of Finnish employees, each person's heart rate variability during the first hours "
                + "of sleep was lower on nights after drinking than on nights without, and more so after more drinks.",
            population: "Working adults in Finland, about half of them women",
            caveats: [
                "The study measured RMSSD with a chest strap during sleep. Apple Watch reports SDNN from short "
                    + "readings, so the two measures aren't directly comparable.",
                "Drinks were self-reported, and the study observed what people did rather than assigning alcohol.",
                groupsCaveat,
            ],
            strength: .moderate,
            sources: [pietila2018],
            surfaces: [.patternNote]
        ),
        EvidenceCard(
            id: "alcohol.restingHeartRate.nextNight",
            matches: [.correlation(x: .alcohol, y: .restingHeartRate, lag: 1)],
            matchQuality: .indirect,
            direction: .higher,
            statement:
                "In a large study of Finnish employees, heart rate during the first hours of sleep was higher on "
                + "nights after drinking, and more so after more drinks. The study measured heart rate during sleep, "
                + "not resting heart rate.",
            population: "Working adults in Finland, about half of them women",
            caveats: [
                "Heart rate during sleep isn't the same as Apple Health's resting heart rate.",
                "Drinks were self-reported, and the study observed what people did rather than assigning alcohol.",
                groupsCaveat,
            ],
            strength: .moderate,
            sources: [pietila2018],
            surfaces: [.patternNote]
        ),
        EvidenceCard(
            id: "caffeine.sleepDuration.nextNight",
            matches: [.correlation(x: .caffeine, y: .sleepDuration, lag: 1)],
            direction: .lower,
            statement:
                "Across controlled studies of adults, caffeine was followed by shorter sleep, more time to fall "
                + "asleep and less deep sleep. The differences were larger when caffeine was taken closer to bedtime.",
            population: "Adults, mostly in laboratory studies",
            caveats: [
                "Vivra records how much caffeine was logged, not when.",
                "People vary in how sensitive they are to caffeine.",
                groupsCaveat,
            ],
            strength: .consistent,
            sources: [gardinerCaffeine2023],
            surfaces: [.patternNote]
        ),
        EvidenceCard(
            id: "workoutDay.sleepDuration",
            matches: [.groupDifference(.workoutDay, outcome: .sleepDuration)],
            direction: .higher,
            statement:
                "Across studies of adults, sleep was slightly longer after single exercise sessions and with "
                + "regular exercise, and regular exercise went with higher ratings of sleep quality. The differences "
                + "in sleep time were small.",
            population: "Adults; studies of single sessions and of regular exercise",
            caveats: [
                "Results varied with age, sex, the type of exercise and the time of day.",
                "Most of the difference was in how people rated their sleep.",
                groupsCaveat,
            ],
            strength: .consistent,
            sources: [kredlow2015],
            surfaces: [.patternNote]
        ),
        EvidenceCard(
            id: "steps.sleepDuration.nextNight",
            matches: [.correlation(x: .steps, y: .sleepDuration, lag: 1)],
            direction: .noConsistentDifference,
            statement:
                "In studies that followed adults day by day, more active days weren't consistently followed by "
                + "longer sleep that night. The links that were found were small and varied between studies.",
            population: "Adults followed for days to weeks",
            caveats: [
                "Most links in the review were between people rather than within the same person.",
                groupsCaveat,
            ],
            strength: .moderate,
            sources: [atoui2021],
            surfaces: [.patternNote]
        ),
        EvidenceCard(
            id: "exercise.hrv.nextDay",
            matches: [.correlation(x: .exerciseMinutes, y: .heartRateVariability, lag: 1)],
            matchQuality: .indirect,
            direction: .lower,
            statement:
                "In studies of athletes and active adults, heart rate variability was lower after aerobic exercise "
                + "and returned to usual within about a day after easy sessions. These studies measured how hard "
                + "people exercised, not for how long.",
            population: "Athletes and active adults doing aerobic exercise",
            caveats: [
                "Recovery took two days or more after hard sessions.",
                "The studies measured RMSSD; Apple Watch reports SDNN.",
                groupsCaveat,
            ],
            strength: .moderate,
            sources: [stanley2013],
            surfaces: [.patternNote]
        ),
        EvidenceCard(
            id: "sleep.mood.experiments",
            matches: [.correlation(x: .sleepDuration, y: .mood, lag: 0)],
            direction: .higher,
            statement:
                "Across experiments in which people's sleep was cut short, they reported less positive mood "
                + "afterwards, and somewhat more negative mood.",
            population: "Adults and young people without known health conditions, in experiments",
            caveats: [
                "Sleep loss in experiments is often larger than an ordinary short night.",
                groupsCaveat,
            ],
            strength: .consistent,
            sources: [tomaso2021, palmer2024],
            surfaces: [.patternNote]
        ),
        EvidenceCard(
            id: "sleep.mood.daily",
            matches: [.correlation(x: .sleepDuration, y: .mood, lag: 0)],
            direction: .higher,
            statement:
                "In studies that followed people day by day, shorter or lower-rated nights were generally followed "
                + "by lower mood the next day. The links were weaker when a device measured sleep than when people "
                + "rated it.",
            population: "Mixed groups, including shift workers",
            caveats: [
                "Vivra measures sleep with a device, where the links were weaker.",
                groupsCaveat,
            ],
            strength: .moderate,
            sources: [hickman2024],
            surfaces: [.patternNote]
        ),
        EvidenceCard(
            id: "sleep.energy.nextDay",
            matches: [.correlation(x: .sleepDuration, y: .energyLevel, lag: 0)],
            matchQuality: .indirect,
            direction: .higher,
            statement:
                "Across experiments, after a single night with sleep cut to a few hours, people rated themselves as "
                + "sleepier. These studies measured sleepiness, not the energy level Vivra logs.",
            population: "Adults in sleep experiments",
            caveats: [
                "The nights in these studies were much shorter than an ordinary short night.",
                groupsCaveat,
            ],
            strength: .consistent,
            sources: [wust2024],
            surfaces: [.patternNote]
        ),
        EvidenceCard(
            id: "sleep.stress.nextDay",
            matches: [.correlation(x: .sleepDuration, y: .stressLevel, lag: 0)],
            matchQuality: .indirect,
            direction: .lower,
            statement:
                "Across experiments in which sleep was cut short or broken up, people reported more anxious feelings "
                + "afterwards. These studies measured anxiety, not the stress level Vivra logs.",
            population: "People without known health conditions, in experiments",
            caveats: [
                "Sleep loss in experiments is often larger than an ordinary short night.",
                groupsCaveat,
            ],
            strength: .consistent,
            sources: [palmer2024],
            surfaces: [.patternNote]
        ),
        EvidenceCard(
            id: "sleep.hrv.nextDay",
            matches: [.correlation(x: .sleepDuration, y: .heartRateVariability, lag: 0)],
            direction: .mixed,
            statement:
                "Across trials in which people went without sleep, one measure of heart rate variability, RMSSD, "
                + "was lower afterwards. SDNN, the measure Apple Watch reports, didn't differ clearly.",
            population: "Adults in sleep deprivation trials",
            caveats: [
                "The trials used different recording methods and lengths of sleep loss.",
                groupsCaveat,
            ],
            strength: .moderate,
            sources: [zhang2025],
            surfaces: [.patternNote]
        ),
        EvidenceCard(
            id: "mindfulness.stress",
            matches: [.correlation(x: .mindfulMinutes, y: .stressLevel, lag: 0)],
            matchQuality: .indirect,
            direction: .lower,
            statement:
                "In studies of adults without known health conditions, people who took part in a mindfulness "
                + "programme lasting several weeks reported less stress afterwards. These studies measured "
                + "programmes over weeks, not minutes on one day.",
            population: "Adults from the general population",
            caveats: [
                "On a single day, people may meditate more when they feel stressed, so a same-day link can run "
                    + "either way.",
                "Studies varied a lot.",
                groupsCaveat,
            ],
            strength: .moderate,
            sources: [khoury2015],
            surfaces: [.patternNote]
        ),
        EvidenceCard(
            id: "mindfulness.sleep",
            matches: [.correlation(x: .mindfulMinutes, y: .sleepDuration, lag: 1)],
            matchQuality: .indirect,
            direction: .higher,
            statement:
                "In trials, people who learned mindfulness meditation rated their sleep quality higher than people "
                + "in some comparison groups. These trials measured how people rated their sleep, not how long they "
                + "slept.",
            population: "Adults in randomised trials",
            caveats: [
                "There was no difference compared with established sleep programmes.",
                groupsCaveat,
            ],
            strength: .moderate,
            sources: [rusch2019],
            surfaces: [.patternNote]
        ),
        EvidenceCard(
            id: "stress.sleep.nextNight",
            matches: [.correlation(x: .stressLevel, y: .sleepDuration, lag: 1)],
            matchQuality: .indirect,
            direction: .lower,
            statement:
                "In a six-week diary study, nights after days with more stress and more worry at bedtime were rated "
                + "as lower-quality sleep. The study measured how people rated their sleep, not how long they slept.",
            population: "Working adults in Sweden",
            caveats: [
                "A small study, and everything was self-reported.",
                groupsCaveat,
            ],
            strength: .limited,
            sources: [akerstedt2012],
            surfaces: [.patternNote]
        ),
        EvidenceCard(
            id: "activity.mood.sameDay",
            matches: [
                .correlation(x: .steps, y: .mood, lag: 0), .correlation(x: .exerciseMinutes, y: .mood, lag: 0),
            ],
            direction: .higher,
            statement:
                "In studies that followed people through their day, being more active was followed by more positive "
                + "mood over the next few hours. More positive mood was also followed by more activity, so the link "
                + "ran both ways.",
            population: "Adults in everyday life",
            caveats: [
                "Most studies were small.",
                groupsCaveat,
            ],
            strength: .moderate,
            sources: [liao2015],
            surfaces: [.patternNote]
        ),
    ]

    // MARK: Background cards for metric detail

    static let contextCards: [EvidenceCard] = [
        EvidenceCard(
            id: "caffeine.timing",
            matches: [.metricContext(.caffeine)],
            direction: .notApplicable,
            statement:
                "In a small study, a large dose of caffeine taken as early as six hours before bed was followed by "
                + "less sleep, as measured by a monitor at home.",
            population: "Adults who usually slept well",
            caveats: [
                "A very small study.",
                "The dose was large, about four cups of coffee.",
            ],
            strength: .limited,
            sources: [drake2013],
            surfaces: [.metricDetail]
        ),
        EvidenceCard(
            id: "exercise.evening.sleep",
            matches: [.metricContext(.workoutMinutes)],
            direction: .notApplicable,
            statement:
                "In studies of single evening workouts in adults without sleep problems, sleep afterwards wasn't shorter or more "
                + "broken overall, and deep sleep was slightly higher. Hard exercise ending within about an hour of "
                + "bedtime was the exception.",
            population: "Adults without sleep problems",
            caveats: [
                "Vivra doesn't use workout timing or intensity.",
                "The finding about hard exercise near bedtime rests on few studies.",
            ],
            strength: .moderate,
            sources: [stutz2019],
            surfaces: [.metricDetail]
        ),
        EvidenceCard(
            id: "restingHeartRate.withinPerson",
            matches: [.metricContext(.restingHeartRate)],
            direction: .notApplicable,
            statement:
                "In a large study of wearable users, resting heart rate differed widely between people but stayed "
                + "fairly steady within each person from week to week, with a small rise in winter.",
            population: "US adults wearing wrist trackers",
            caveats: [
                "Fitbit users in the United States.",
                "Some people had weeks when it shifted much more.",
            ],
            strength: .moderate,
            sources: [quer2020],
            surfaces: [.metricDetail]
        ),
        EvidenceCard(
            id: "hrv.dayToDay",
            matches: [.metricContext(.heartRateVariability)],
            direction: .notApplicable,
            statement:
                "In studies of athletes, heart rate variability changed much more from day to day than resting heart "
                + "rate did, and averages over several days followed longer-term changes more closely than single "
                + "days.",
            population: "Athletes measured each morning",
            caveats: [
                "The studies measured RMSSD each morning; Apple Watch takes SDNN readings at different times of day."
            ],
            strength: .moderate,
            sources: [buchheit2014],
            surfaces: [.metricDetail]
        ),
        EvidenceCard(
            id: "hrv.measurement",
            matches: [.metricContext(.heartRateVariability)],
            direction: .notApplicable,
            statement:
                "Research on heart rate variability has found that values depend on how long the recording is, and "
                + "on age and sex, so values from recordings of different lengths aren't directly comparable.",
            population: "Reviews of recording methods",
            caveats: ["Most reference values come from laboratory recordings."],
            strength: .consistent,
            sources: [shaffer2017],
            surfaces: [.metricDetail]
        ),
        EvidenceCard(
            id: "sleep.tracking",
            matches: [.metricContext(.sleepDuration)],
            direction: .notApplicable,
            statement:
                "In a lab study of six wearable devices, including Apple Watch, the devices agreed well with lab "
                + "recordings on when people were asleep or awake, and less closely on individual sleep stages.",
            population: "Young adults without sleep problems, one night each",
            caveats: [
                "One night in a laboratory, with an older Apple Watch model.",
                "Agreement may differ at home and with newer software.",
            ],
            strength: .limited,
            sources: [miller2022],
            surfaces: [.metricDetail]
        ),
        EvidenceCard(
            id: "mindfulness.hrv",
            matches: [.metricContext(.mindfulMinutes)],
            direction: .notApplicable,
            statement:
                "Across trials, mindfulness and meditation programmes weren't clearly followed by higher resting "
                + "heart rate variability, and results varied a lot between trials.",
            population: "Adults in randomised trials",
            caveats: ["The trials measured a different form of heart rate variability from Apple Watch's SDNN."],
            strength: .mixed,
            sources: [brown2021],
            surfaces: [.metricDetail]
        ),
    ]

    // MARK: Kept for the record, never shown

    static let recordOnlyCards: [EvidenceCard] = [
        EvidenceCard(
            id: "shorterSleep.restingHeartRate.betweenPeople",
            matches: [.groupDifference(.shorterSleep, outcome: .restingHeartRate)],
            direction: .notApplicable,
            statement:
                "In a large study of wearable users, average resting heart rate was lowest among people who usually "
                + "slept about seven to seven and a half hours a night.",
            population: "US adults wearing wrist trackers",
            caveats: ["This compares people with each other, not one person's nights."],
            strength: .moderate,
            sources: [quer2020],
            status: .referenceOnly,
            surfaces: [],
            note:
                "Evidence about differences between people, not between one person's nights, so it isn't shown "
                + "under a personal pattern. No within-person source found yet."
        ),
        EvidenceCard(
            id: "alcohol.remSleep",
            matches: [],
            direction: .lower,
            statement:
                "In lab studies, evening alcohol was followed by less REM sleep and a later first REM period, "
                + "starting from about two standard drinks.",
            population: "Adults without sleep problems, in laboratory studies",
            caveats: ["Apple Watch estimates sleep stages; the studies measured them with brain recordings."],
            strength: .consistent,
            sources: [gardinerAlcohol2025],
            status: .referenceOnly,
            surfaces: [],
            note: "Vivra has no REM sleep metric yet (separate work, PLAN Phase 8 decision 7)."
        ),
        EvidenceCard(
            id: "steps.depression",
            matches: [],
            direction: .notApplicable,
            statement: "",
            population: "",
            caveats: [],
            strength: .moderate,
            sources: [],
            status: .excluded,
            surfaces: [],
            note:
                "Excluded (owner, Phase 8): a clinical condition. Source considered: Bizzozero-Peroni B, et al. "
                + "JAMA Netw Open. 2024;7(12):e2451208. doi:10.1001/jamanetworkopen.2024.51208."
        ),
        EvidenceCard(
            id: "illness.signals",
            matches: [],
            direction: .notApplicable,
            statement: "",
            population: "",
            caveats: [],
            strength: .moderate,
            sources: [],
            status: .excluded,
            surfaces: [],
            note:
                "Excluded (owner, Phase 8): illness detection from heart rate, breathing or temperature. Sources "
                + "considered: Radin JM, et al. Lancet Digit Health. 2020;2(2):e85–e93; Miller DJ, et al. PLoS One. "
                + "2020;15(12):e0243693."
        ),
        EvidenceCard(
            id: "wristTemperature.cycle",
            matches: [],
            direction: .notApplicable,
            statement: "",
            population: "",
            caveats: [],
            strength: .moderate,
            sources: [],
            status: .excluded,
            surfaces: [],
            note:
                "Held (owner, Phase 8) until the owner decides: reproductive health is sensitive. Sources "
                + "considered: Maijala A, et al. BMC Womens Health. 2019;19:150; Wang Z, et al. Hum Reprod. "
                + "2025;40(3):469–478."
        ),
    ]
}
