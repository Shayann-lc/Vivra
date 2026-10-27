# UX research: what people say about Whoop, Fitbit, Apple Health and Apple Fitness

Done at the start of Phase 3 (October 2026), at the owner's request, to inform
Vivra's interface. The sources are public: App Store reviews, press coverage of
redesigns, forum threads, and one peer-reviewed study on streaks.

**Caveat.** Most of this is anecdotal, and complaints are over-represented
(people review when something annoys them). Treat it as a list of failure modes
to avoid, not as measured user preference. The overall App Store ratings are
high: Whoop 4.8 from 91K ratings, and Fitbit 4.5 from 709K.

## What people complain about

### 1. Big tiles, empty space, and numbers that are hard to find

- **Google Health, the 2026 replacement for the Fitbit app**, drew a backlash for
  oversized tiles that crowd key data into a few cards and leave large blank
  areas ("Why so much white wasted space?"). Users said the layout gets in the
  way of seeing their numbers.
  ([PiunikaWeb](https://piunikaweb.com/2026/05/25/google-health-app-fitbit-backlash-missing-features-ui-changes/),
  [Android Headlines](https://www.androidheadlines.com/2026/05/fitbit-users-wake-up-to-an-absolute-dogsht-app-redesign.html))
- **The 2023 Fitbit redesign:** reviewers said metrics were "not as quick or easy
  to scroll through", graphics were "excessively large" while key icons were
  tiny, and colours "blend together".
  ([App Store reviews](https://apps.apple.com/us/app/fitbit-health-fitness/id462638897?see-all=reviews),
  [TechRadar](https://www.techradar.com/health-fitness/fitbit-fans-arent-happy-about-the-official-apps-redesign-heres-why))
- **Apple Health:** users find data hard to locate unless they first pin it to
  Favorites. Even then, Favorites becomes "a long list of things that I don't
  need to know every day".
  ([MacRumors forum](https://spy.macrumors.com/threads/health-app-redesign.2198289),
  [Apple Support Community](https://discussions-kr-prz.apple.com/thread/251071131))

### 2. AI text that pushes the data down

- **Google Health:** coach prompts and AI text appear before the stats. Users
  called it "AI slop", found the coach intrusive, and tapped it by accident.
  ([PiunikaWeb](https://piunikaweb.com/2026/05/25/google-health-app-fitbit-backlash-missing-features-ui-changes/))

### 3. Not being able to choose what matters

- **Whoop:** reviewers say they're "tied to what Whoop deems important". They
  can't add custom tracking categories, can't adjust chart scales, and can't see
  more than a week on the phone.
  ([App Store reviews](https://apps.apple.com/us/app/whoop/id933944389?see-all=reviews))
- **Google Health:** you can't simply make sleep the main tile. You have to enable
  it and drag it up a feed.
  ([PiunikaWeb](https://piunikaweb.com/2026/05/25/google-health-app-fitbit-backlash-missing-features-ui-changes/))

### 4. Scores without context

- **Whoop's** three scores (Recovery, Strain, Sleep) are praised for "simplifying
  the concepts", but a common complaint is that a score didn't match how the
  person felt, with nothing to show why.
  ([App Store reviews](https://apps.apple.com/us/app/whoop/id933944389?see-all=reviews),
  [Medium, 6-month review](https://tmrss.medium.com/comprehensive-whoop-review-6-months-in-3877886dd996),
  [GearJunkie](https://gearjunkie.com/health-fitness/whoop-4-0-review))
- **Whoop's** 2025 home screen puts the three scores up front, with the details
  one tap away. The company says it rebuilt it from member feedback.
  ([Whoop](https://www.whoop.com/us/en/thelocker/the-all-new-whoop-home-screen/))

### 5. Streaks that punish real life

- **Apple Fitness:** Activity rings have no rest days. Users complain that long
  streaks end for reasons outside their control, such as forgetting to start a
  workout or being ill.
  ([Jon Westfall](https://jonwestfall.com/2021/08/rest-days-that-dont-break-your-apple-activity-streaks/))
  iOS 26.1 added manual workout logging specifically so a forgotten workout no
  longer breaks a streak.
  ([9to5Mac](https://9to5mac.com/2025/11/07/ios-26-1-lets-you-close-activity-rings-even-if-you-forget-to-start-a-workout/),
  [Gadget Hacks](https://apple.gadgethacks.com/news/ios-261-manual-workout-logging-finally-closes-activity-rings/))
- **Gentler Streak**, a competitor, is praised for exactly this: rest days keep the
  streak alive. A reviewer said they "no longer feel lazy" on days off.
  ([App Store](https://apps.apple.com/us/app/gentler-streak-fitness-tracker/id1576857102),
  [Yahoo / Digital Trends](https://sg.news.yahoo.com/fitness-app-shows-apple-better-180000454.html))
- **Research:** Silverman and Barasch, *Journal of Consumer Research* (2023),
  found that people adopt a streak as a goal of its own. When a streak breaks,
  they become less likely to keep doing the behaviour: in one fitness-app study,
  58% continued after a broken streak against 66% after an intact one. People
  also pay costs to repair a broken streak.
  ([Psychology Today summary](https://www.psychologytoday.com/us/blog/ulterior-motives/202306/how-broken-streaks-sap-motivation))

### 6. Redesigns that remove things people relied on

- Both Fitbit redesigns removed views people used: hourly steps, stairs,
  achievements and badges. The removals drew the angriest reviews.
  ([App Store reviews](https://apps.apple.com/us/app/fitbit-health-fitness/id462638897?see-all=reviews),
  [PiunikaWeb](https://piunikaweb.com/2026/05/25/google-health-app-fitbit-backlash-missing-features-ui-changes/))

### What people liked

- Fitbit's gentle hourly move reminders came up as "motivating".
- Whoop's few clear headline numbers, with the details one tap away.
- Gentler Streak's forgiveness.

## What Vivra does with this

| Finding | Vivra design rule |
|---|---|
| Big tiles bury numbers (1) | **Numbers first, compact.** The Today screen opens with a dense list: last night's sleep, resting heart rate, HRV and steps, each on one line. No hero tiles, no decorative empty space. |
| AI pushes data down (2) | **No generated text on the home screen.** The one "worth noticing" line is template text drawn from computed findings. Model-written summaries stay in Insights, below their headline. |
| Can't choose (3) | **You choose what's on Today.** Cards can be shown, hidden and reordered in one sheet, with no feed dragging. Every metric opens a 28-day view. |
| Scores without context (4) | **No black-box scores.** Every number sits next to *your usual* (your 28-day median, with the usual range on tap), plus how many days it's based on and where the data came from. Vivra never invents a composite score. |
| Punishing streaks (5) | **Forgiving runs.** Runs are kept going by earned pauses. You can log for earlier today or yesterday, so forgetting doesn't cost anything. Total days logged is shown beside the current run, so a reset never wipes out visible progress. There's never a "streak lost" message, only "Welcome back". |
| Removed features (6) | **Additive changes only.** Everything from Phases 1 and 2 stays and is reorganised, not removed. |
| Gentle reminders liked | **One optional reminder a day** at a time you choose. It's skipped once you've logged that day, and it stops after a week of not opening the app. |
