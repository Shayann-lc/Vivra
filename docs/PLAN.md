# Vivra — Architecture and Phased Plan

Status: **approved** (all of §11, with bundle ID and team as placeholders until signing). Phases 0–3 are done in code, with CI green. The device checks for Phases 1–3 (`docs/DEVICE_TEST.md`) are pending with the owner. Phase 4 is approved and in progress.

## 1. Decisions already made

| # | Decision | Answer |
|---|----------|--------|
| 1 | Leaderboard | **Dropped from v1.** Nothing about it is built. Gamification state is modelled so a leaderboard can be added later without a migration. |
| 2 | Apple Watch companion app | **Not in v1.** Watch data still arrives through HealthKit. |
| 3 | Minimum iOS | **iOS 26.** Foundation Models and State of Mind are both available. |
| 4 | Branching | Commit straight to `main`. |
| 5 | Direct Strava API integration | **Not building it** (approved). See §8. Workouts that Strava writes to Apple Health are still read through HealthKit. |
| 6 | Dependencies | GRDB.swift + SQLCipher.swift (app runtime), XcodeGen (dev only). GRDB is **vendored** in `Vendor/GRDB`, because its SQLCipher build under SwiftPM requires a fork with an edited manifest (see `Vendor/GRDB/VENDORED.md`). |
| 7 | Writing back to HealthKit | Opt-in write of mood (State of Mind) and drinks (water, caffeine, alcohol), Phase 2. |
| 8 | Workout routes | **Not read or stored** in Phase 2 (owner, Phase 2 kickoff). GPS traces are the most sensitive data Vivra could hold, and nothing uses them yet. Revisit with a feature that needs them. |
| 10 | VO2 max norms | **Every build:** Vivra points to Apple Health's Cardio Fitness levels (FRIEND-based) and ships no VO2 max table. **The owner's own non-commercial build** (`VIVRA_NONCOMMERCIAL`) also shows FRIEND 2015 treadmill medians, with citation (owner, Phase 4 kickoff). Licensing details are in `docs/NORMS.md`. |
| 9 | Quick-log entry points | Widgets, controls and Shortcuts **open the app** at the Quick Log screen (owner, Phase 2 kickoff). The extension has no database access, no App Group and no shared Keychain item. |

## 2. Principles, restated as engineering rules

- **No network code**, apart from the system frameworks Apple runs on its own (HealthKit, Foundation Models). There is no `URLSession` use in v1. CI fails if anyone adds it (see §10).
- **No third-party SDKs** that collect data: no analytics, crash reporters or ads. Crash data comes only from Apple's opt-in diagnostics.
- **The LLM never produces a number.** The Swift insight engine computes every figure. The model only words the findings it is given, and its output is checked against them (see §6.4).
- **No health values in logs.** Logging goes through one `Log` wrapper that only accepts values marked as safe (counts, durations, error codes). Anything else is logged with `privacy: .private`.
- **Injected clocks and calendars.** No `Date()` or `Calendar.current` calls inside engine or sync code. Tests run with a fixed clock, time zone and locale.

## 3. Architecture

```
Vivra.xcodeproj  (app target, iOS 26)
└── App/                     SwiftUI app: screens, AppModel, app lock, preferences
Packages/
├── VivraCore                Platform-independent; builds and tests on Linux too
│   ├── VivraLogging         StaticString-only Log wrapper
│   ├── VivraModel           Value types, injected Clock and DayCalendar
│   ├── SyncCore             SyncEngine and the HealthDataSource/SyncStore protocols
│   ├── InsightEngine        Sleep nights, daily metrics, findings, dashboard snapshot
│   └── NarrativeCore        Style rules, validator, templates, prompts, composer
├── VivraStore               Encrypted database, migrations, HealthRepository (Apple only)
├── HealthSync               HealthKit adapter: anchored queries, observers (Apple only)
├── Narrative                Foundation Models narrator (Apple only)
├── Gamification             (Phase 3)
└── Norms                    (Phase 4)
```

How the pieces depend on each other:
`App → {Narrative, HealthSync, VivraStore} → VivraCore`. Every rule that matters (sync
correctness, statistics, what the model may say) is in `VivraCore`, which has no Apple
dependencies, so it's tested on Linux as well as in CI. In Phase 1 the views live in the
app target, not a separate `VivraUI` package; they can be split out when a widget or
another target needs them.

### 3.1 Data flow

```
HealthKit ──(anchored queries / background delivery)──▶ HealthSync ──▶ VivraStore (encrypted)
In-app logs ───────────────────────────────────────────────────────────▶ VivraStore
VivraStore ──▶ InsightEngine.daily rollups ──▶ [Finding]  (numbers, n, confidence)
[Finding] ──▶ Narrative (Foundation Models, @Generable) ──▶ Validator ──▶ UI
                                    └── on failure or no model ──▶ Template renderer ──▶ UI
```

### 3.2 HealthKit sync

- Every type is read through a `HealthDataSource` protocol. The real implementation uses `HKHealthStore`, and tests use a fake that returns fixed data.
- **Incremental sync:** one `HKAnchoredObjectQuery` per type. Each anchor is stored in the database in the same transaction as the samples it produced, so a crash can't leave the two out of step. Deleted objects are applied as deletes.
- **Background delivery:** `enableBackgroundDelivery` is called for each type at a frequency that suits it (`.immediate` for workouts and State of Mind, `.hourly` for heart data, `.daily` for body measurements). Each observer query's completion handler is called only after the database commit.
- **Locked device:** HealthKit data can't be read while the device is locked, and our database uses Data Protection `complete`, so it can't be opened then either. A sync that fires while locked does nothing, and the next unlock or app launch catches up through the anchors. This is the correct behaviour, not a bug.
- **Permissions:** requested in separate groups (sleep, heart, activity, and so on), each with its own explanation screen. iOS never tells an app whether *read* access was denied, so "no data" is shown neutrally with a link to Settings.
- **Sleep stages:** stored as raw intervals. "Sleep nights" are assembled in the engine. Overlapping sources (iPhone, Watch, third-party apps) are resolved by a source-priority list (Watch first), applied deterministically.
- **ECG and irregular-rhythm events:** only the date and classification label HealthKit provides are stored and listed. They are never used in insights or narrative.

### 3.3 Encrypted storage — needs dependency approval

The requirement is Data Protection `complete` **plus** an encrypted store. SwiftData has no database-level encryption: it relies only on file protection. My recommendation:

- **GRDB.swift with SQLCipher.** The 256-bit key is generated on first launch and stored in the Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, so it is never in iCloud backups or device migrations. The database file is also set to `NSFileProtectionComplete`.
- How SQLCipher is wired in: GRDB v7.11.1 is vendored with upstream's documented `GRDB+SQLCipher` manifest changes, against SQLCipher.swift 4.19.0 (pinned exactly). The key goes to SQLCipher in raw-key form (`x'…'`), which skips the passphrase KDF.
- Fallback if you don't want the dependency: SwiftData with `complete` file protection, plus CryptoKit `AES.GCM` encryption of the sensitive columns (notes, mood text). This is weaker, because queries and indexes on encrypted fields stop working.

Schema outline:
- `sample` (type, start, end, value, unit, source, hk_uuid)
- `sleep_interval`
- `workout`
- `log_entry` (kind, value, note, timestamp)
- `sync_anchor` (type, anchor_blob)
- `daily_rollup` (a cache the engine can always rebuild)
- `finding_cache`
- `report` (kind, period, findings JSON, narrative text, generator: model|template)
- `settings`

Every migration is written as a numbered `DatabaseMigrator` step with a test.

## 4. Security and privacy controls

| Control | Implementation |
|---|---|
| Encryption at rest | SQLCipher, plus `NSFileProtectionComplete` on the database and any exports |
| App lock (optional) | `LocalAuthentication` (Face ID, or device passcode as fallback). The app locks on background after a timeout the user chooses (immediately, 1 min or 5 min). A privacy cover hides the app-switcher snapshot |
| Logs | A `Log` wrapper around `os.Logger`. CI rejects `print(` and string interpolation of model types in log calls |
| Export | A JSON file (plus CSV per table) written to a temporary file with complete protection and handed to the share sheet. It is deleted when the share sheet closes |
| Delete everything | Closes the database, deletes the file and WAL, deletes the Keychain key, clears UserDefaults and the cache. Then explains that HealthKit permissions can only be revoked in Settings and that Apple Health data itself is untouched |
| Privacy manifest | `PrivacyInfo.xcprivacy` declaring no tracking and no data collected, plus the required-reason API entries |
| Disclaimer | Shown during onboarding (must be acknowledged), in Settings, and in the footer of every report |

## 5. Insight engine (deterministic Swift)

- **Daily rollups:** one row per local calendar day. Sleep is attributed to the day you wake up. Each row holds sleep duration and stages, resting HR, HRV (SDNN) average, steps, active energy, exercise minutes, alcohol, caffeine, mood and energy logs.
- **Correlations (Phase 2):** Spearman's ρ is the default, because it handles outliers and non-normal data. Each pair records n, ρ and a 95% confidence interval (Fisher z).
- **Lagged effects:** the same calculation applied to day *t* → day *t+1* pairs, for example alcohol to next-night HRV, or late workout to sleep latency.
- **Group differences:** for example, nights shorter than the person's median compared with longer ones, on that day's resting HR. The result is a difference of medians, with a bootstrap 95% interval using a fixed seed (so it is deterministic) and a **Mann–Whitney U** p-value (normal approximation with tie and continuity corrections, checked against scipy). A permutation test on the median difference was tried first. It had almost no power on tied data such as whole-minute sleep, so it was replaced.
- **Gates before anything is shown to the user:**
  - n ≥ 14 paired days, and n ≥ 7 in each group for group differences.
  - |ρ| ≥ 0.3 (correlations), or a difference at least a per-metric minimum (1 bpm resting HR, 15 min sleep) with a 95% interval that excludes zero.
  - Benjamini–Hochberg false-discovery control (q = 0.10) across all the pairs tested in a report.
- **Confidence levels:** high when the smaller group has at least 20 days and the adjusted p ≤ 0.01, medium for at least 10 days and p ≤ 0.05, otherwise low. Stability across the window is planned for Phase 2.
- **Trends:** Theil–Sen slope over 28 or 90 days.
- **Anomalies:** robust z-score (median and MAD) against the user's own 28-day baseline.
- **Wording:** `Finding` is a structured value carrying metric IDs, direction, numbers, n, confidence and window. It never contains prose. Causal words are banned at the type level, because the narrative layer only receives "associated with" templates.
- **Typical-range flags:** if a metric falls outside a bundled typical range, the finding carries a `suggestProfessional` flag. The UI shows "If you have questions about this, consider talking with a healthcare professional." It never says what the value means.

Every statistic is covered by unit tests with known answers, and every report type by golden-file tests.

## 6. On-device narrative (Foundation Models)

1. **Availability:** `SystemLanguageModel.default.availability` is checked. The model needs a device with Apple Intelligence that has it turned on. When it isn't available, a **template renderer** produces the same report from the same findings. The report says which generator was used.
2. **Structured output:** the model generates a `@Generable` struct (headline, a few bullets, each referring back to a finding ID) rather than free text. This keeps the output short and checkable.
3. **Style guide:** `docs/STYLE_GUIDE.md` (written in Phase 1) sets the tone: neutral, encouraging, observational. It covers banned words ("bad", "failed", "should", "poor", "diagnose", "causes", "risk", and so on), always using "on days when…" phrasing, and no imperatives about health. It is compiled into the system instructions for every session.
4. **Validator** (deterministic, runs on every output):
   - Every number in the text must match a number in the referenced findings (after a defined rounding).
   - Every bullet must reference a real finding ID.
   - The text must contain no banned words and no causal phrases.
   If validation fails, the model gets one retry with the violations listed. A second failure uses the template renderer.
5. **Context budget:** the on-device model's context window is small, so the input is capped at the top 8 findings by confidence × effect size.

## 7. Feature scope by phase

### Phase 0 — Foundations (no user-facing features)
- Xcode project, local packages, iOS 26 deployment target, Swift 6 strict concurrency, `swift-format` config.
- CI on GitHub Actions macOS runners: build, run unit tests, and the guard checks (no networking APIs, no `print`, no banned imports).
- Spike: GRDB with SQLCipher opens, encrypts and migrates. Tests check that the file has no plaintext SQLite header or values, that a wrong key is refused, that the database reopens with the right key, and that the directory has `complete` protection.
- **Done when:** CI is green on `main` (Linux checks, plus build and all tests on an iOS 26 simulator), and the placeholder app launches on a simulator and reports that secure storage is ready.
- The owner should also run it once on a physical device, but that is not a gate.

### Phase 1 — The deliverable you specified
- Onboarding: what Vivra is, the disclaimer (must be acknowledged), grouped HealthKit permission requests.
- HealthSync for **sleep** (stages, time in bed), **heart** (HR, resting HR, HRV SDNN, walking HR average, VO2 max) and **workouts** (type, duration, energy, distance; no routes yet). Anchored queries and background delivery.
- Encrypted store with migrations.
- Dashboard: a card per data family for the last 7 days (sleep duration and stages, resting HR and HRV trend, workouts list) using Swift Charts.
- Weekly summary: Phase 1 engine subset → Foundation Models narrative → validator → template fallback. The subset is weekly averages over the last 7 complete days next to the 7 before (sleep, resting HR, HRV, walking HR, VO2 max, workout count and minutes; a metric needs 3 days), plus two lagged patterns over 90 days when the gates pass:
  - a night shorter than the person's median, compared on that day's resting HR;
  - a workout day (20 minutes or more) against a day with none, compared on the following night's sleep.
- Strava-sourced workouts are left out of reports (and so out of the model) by default, and kept on the dashboard. `SourcePolicy.includeAll` switches this (§8).
- Settings: app lock, delete everything, disclaimer.
- `docs/STYLE_GUIDE.md`.
- **Definition of done:**
  1. On a physical device running iOS 26 with Apple Health data, a fresh install asks for permissions, syncs the last 90 days, and shows the dashboard.
  2. A new sleep night or workout appears after the next background delivery or launch, with no duplicates (verified by deleting a workout in Health and seeing it disappear).
  3. The database file can't be opened without the key (verified with `sqlite3`).
  4. A weekly summary is produced on an Apple Intelligence device, and a template summary on one without it. Both pass the validator.
  5. Unit tests cover the engine subset, sync anchor handling (with the fake data source) and the validator. CI is green.
  6. Delete everything leaves no database, key or defaults behind.

### Phase 2 — Full data and logging

**Data**
- New HealthKit read types, each a `HealthDataType` with its own anchor:
  - Activity: steps, active and basal energy, exercise minutes, walking/running distance, stand hours.
  - Mind: State of Mind, mindful minutes.
  - Nutrition: dietary energy, protein, carbohydrates, fat, water, caffeine, alcoholic beverages.
  - Body: weight, body fat, respiratory rate, blood oxygen, sleeping wrist temperature.
  - Heart events: ECG recordings (date and Apple's classification only) and irregular rhythm notifications. They are listed, never interpreted, and never used in insights.
- New permission groups: Activity, Mind, Nutrition, Body. ECG and irregular rhythm join Heart. People who finished onboarding in Phase 1 get a one-time card on the dashboard to review the new groups.
- Cumulative activity totals: iPhone and Watch both record steps, energy, distance and exercise, so summing raw samples double-counts. Daily totals come from a per-day, per-source SQL sum over day boundaries the engine computes in Swift. The engine then keeps the **largest single source** per day. Dietary totals add across sources, excluding Vivra's own written samples.
- Schema v3: `category_event` (stand hours, mindful sessions, irregular rhythm), `state_of_mind`, `ecg_record`, `log_entry`, and `report.kind`.

**Quick logging (under 10 seconds)**
- One screen of chips: mood, energy and stress on 1–5 scales, drinks (water, coffee, tea, alcohol with editable default amounts), meal, and an optional note. **Save** stores everything at one timestamp. Entries from today can be deleted.
- Entry points: a Log tab, an App Shortcut (`OpenQuickLogIntent`), a Control Center / Lock Screen control, and a Home Screen and Lock Screen widget. All of them open the app at Quick Log (decision 9).
- Optional write-back (Settings, off by default): mood becomes a momentary State of Mind (1–5 mapped to valence −1…1), water becomes dietary water, coffee and tea become caffeine, and alcohol becomes alcoholic beverages. The HealthKit UUID is kept with the log entry, and deleting the entry deletes the sample. When samples sync back from HealthKit, anything Vivra wrote is ignored (`SourcePolicy.ownBundleIdentifier`), so nothing is counted twice.

**Insight engine**
- Daily metrics for every type above, plus logged mood, energy and stress. State of Mind valence is mapped onto the same 1–5 scale and averaged with logs.
- **Correlations:** Spearman ρ over a curated catalogue of directional pairs (`PatternCatalog`), same-day or with a one-day lag. Examples: alcohol → next night's HRV, caffeine → next night's sleep, last night's sleep → that day's mood. A curated list keeps multiple testing small and the pairs meaningful.
  - p-value and 95% interval from Fisher z with the Spearman standard error 1.06/√(n−3) (Fieller et al., 1957).
  - Gates: n ≥ 14 paired days, |ρ| ≥ 0.3, an interval that excludes 0, and BH (q = 0.10) across every pattern tested in the report, Phase 1's two group differences included.
  - Each correlation is shown concretely: the outcome's median on days in the top third of X against the bottom third. When at least a third of X is tied at its minimum (for example, days with no alcohol), it compares "none" against "some".
- **Stability:** a pattern is stable when ρ has the same sign in both halves of the window, each with n ≥ 7.
  - High confidence: n ≥ 28, adjusted p ≤ 0.01 and stable.
  - Medium: n ≥ 14 and adjusted p ≤ 0.05, and not unstable.
  - Low: anything else.
- **Trends:** Theil–Sen slope over the last 28 days, with significance from the Mann–Kendall test (tie-corrected), BH across trend tests, n ≥ 14 days with data, and an overall change of at least the metric's minimum effect. Shown as "from about A to about B".
- **Anomalies:** yesterday's or today's value compared with the previous 28 days (n ≥ 14). Robust z = (x − median) / (1.4826 · MAD), flagged at |z| ≥ 3.5 (Iglewicz & Hoaglin). Shown against the person's usual range (10th–90th percentile).
- Typical-range notes (`suggestProfessional`) are added for blood oxygen below 90% and respiratory rate outside 10–24 breaths/min, alongside resting heart rate.
- **Daily check-in:** last night's sleep, plus today's or yesterday's resting HR, HRV, steps, exercise and logged mood, each against its 28-day median. It also includes any anomalies and the single highest-confidence pattern. It uses the same composer, validator and template fallback as the weekly summary.
- An **Insights** tab holds the daily check-in, the weekly summary, and a Patterns list. The list shows every current pattern and trend with its confidence, in template wording only (no model).

**Definition of done**
1. Every new type syncs incrementally with anchors, deletes included. Covered by the fake data source in SyncCore tests and the repository on the simulator.
2. Quick Log saves a mood plus a drink in two taps and Save. The widget, the control and the App Shortcut each open the app at Quick Log (checked on a device).
3. With write-back on, a logged mood appears in Apple Health as State of Mind and a coffee appears as caffeine. Deleting the entry removes both. Synced copies are never counted twice (unit test plus a device check).
4. The engine has known-answer tests: Spearman and Mann–Kendall against scipy, Theil–Sen and robust z by hand. Gates, BH, stability and every finding kind have tests. Every template sentence passes the validator.
5. A daily check-in is produced from the model on an Apple Intelligence device and from templates without one, and both pass the validator.
6. CI is green. `docs/DEVICE_TEST.md` gains the Phase 2 steps.

### Phase 3 — Gamification (rewards logging, not exercise) and a clearer interface

The owner asked for the interface to draw on public reviews of Whoop, Fitbit, Apple Health and Apple Fitness. The findings and the rules they lead to are in `docs/UX_RESEARCH.md`.

**Progress (rewards logging only, never exercise)**
- A **check-in** is one Quick Log save. The **daily goal** is 1 check-in by default (choose 1–3). The goal history is stored, so changing it never rewrites past days.
- **Runs**, not "streaks":
  - Consecutive days that meet the goal.
  - **Pauses** are earned, one per 7 goal days in a run, and you can hold up to two. A missed day uses a pause automatically, so the run continues.
  - A run only resets when a day is missed with no pause left.
  - Today never counts as missed until it's over.
- **Logging for earlier:** Quick Log can log for earlier today or yesterday. Progress is computed from entry times, so a forgotten day can be filled in (the Apple Fitness lesson, `UX_RESEARCH.md` §5).
- **XP, for logging only:** 10 for the first check-in of a day, +5 for each other kind logged that day, capped at 30, plus 5 when the daily goal is met. Levels at 0, 50, 150, 300, 500 … XP (level *n* starts at 25·*n*·(*n*−1)).
- **Achievements:**
  - Consistency: days logged in total, runs of 7 and 30 days, and coming back after a break.
  - Exploring: first weekly summary, first check-in report, opening Patterns, answering every Health permission, trying every kind of log, and turning on Health saving.
- **Everything derived:** all of it is computed from log entries, goal history and an append-only `app_event` log, never stored as counters. That way it can't drift, backfilled logs count, and a future leaderboard could compute XP the same way without a migration (decision 1).
- **Copy:** "Welcome back" after a break. No loss language anywhere: progress copy is checked against `StyleGuide.bannedTerms` and a list of loss phrases in a test.

**Reminders**
- Optional and off by default, offered once after your first save.
- One local notification a day, at a time you choose. It's skipped once today's goal is met.
- Notifications are scheduled 7 days ahead and rescheduled whenever the app opens, so they stop by themselves after a week without opening the app.
- No streak warnings, and no health data in notification text.

**Interface** (rules from `UX_RESEARCH.md`)
- Tabs: **Today**, **Log**, **Insights**, **Progress**. Settings moves to a button in Today's toolbar.
- **Today**, from top to bottom:
  - A compact *at a glance* list of the latest values next to *your usual* (28-day median).
  - A one-line progress strip: today's goal, current run and level.
  - A Quick Log button.
  - One *worth noticing* line: the most notable unusual value or pattern, in template text.
  - The Phase 1–2 cards, which you can show, hide and reorder.
- **Metric detail:** tap any value to see 28 days as a chart with your usual range (10th–90th percentile) shaded, the number of days, the source, and a plain description of the metric (no interpretation).
- **Progress tab:** level and XP, today's goal, the current run and pauses, a 7-day strip (missed days drawn neutrally, never red), total days logged, longest run, achievements, and the daily goal setting.
- After saving, a short confirmation with XP earned and the run. "Welcome back" when returning after a break.

**Definition of done**
1. The progress engine in VivraCore has scenario tests: runs, earning and using pauses, the cap of two, backfilling, goal changes over time, XP and levels, every achievement, welcome back, and today pending. Tests also check the reminder plan (skip once logged, 7 days ahead) and that all progress and reminder copy passes the style checks.
2. Schema v4 (`goal_setting`, `app_event`) with repository tests.
3. Today, metric detail, Progress, the card editor and Quick Log's "when" control are built. App-hosted tests cover saving with a backdated time, goal changes, and recording events.
4. A device check of a reminder arriving and being skipped after logging, and of the Today screen. Steps are in `docs/DEVICE_TEST.md`.
5. CI is green.

### Phase 4 — Deeper reports and reference norms

**Monthly deep-dive**
- A new report kind, `monthly`, covering the last 30 complete days. It includes:
  - every current pattern;
  - trends;
  - each metric averaged over the 30 days next to the 30 days before (a new finding kind, `periodAverage`, with a metric needing at least 10 days in a period).

  Unusual values stay in the daily check-in and "Why do I feel off today?", where they're current.
- The same composer, validator and template fallback as the other reports. It's shown in Insights.

**"Why do I feel off today?"**
- An on-demand report kind, `feelingOff`. The engine collects:
  1. unusual values from today or yesterday;
  2. recent values that differ from your usual by at least the metric's minimum effect;
  3. **patterns that apply today**: a significant pattern whose condition was met by the day before or last night's value. For example, "Yesterday you had 190 mg of caffeine. On days with 190 mg or more, you slept a median of …".
- The model only words these findings, under an extra instruction never to call any of them a reason or cause. The answer is headed "What stood out today", with a fixed note: "Vivra can't tell why you feel a certain way. These are things in your data that stood out, and patterns seen before."

**Reference norms** (`docs/NORMS.md` is the source of truth)
- **Resting heart rate:** CDC NHSR No. 41 percentiles (public domain), by sex and age band.
- **Sleep:** the AASM/SRS recommendation of 7 hours or more (adults 18–60).
- **VO2 max:** decision 10.
- **Comparison profile:** birth year and a reference group (women's or men's tables, or no comparison). It's entered in Settings and stored in the encrypted database. Comparisons stay off until it's set.
- **Wording:** neutral position only ("between the 25th and 50th percentiles"). The citation and caveats are always shown, and there are never category labels.

**Definition of done**
1. Engine tests (Linux):
   - monthly averages and gates;
   - day-context findings, including applicable patterns for both correlations and group differences;
   - percentile placement, including outside the table and at exact values;
   - age-band lookup;
   - every new template passing the validator.
2. Norm values match the primary sources (tests pin a sample of rows), and every norm has a source with a citation.
3. App: monthly and feeling-off reports in Insights, the comparison profile in Settings, and a reference section in metric detail with the citation and caveats. The Apple Health pointer for VO2 max.
4. The `VIVRA_NONCOMMERCIAL` build compiles in CI. The default build contains no FRIEND data.
5. CI is green, and `docs/DEVICE_TEST.md` gains the Phase 4 steps.

### Phase 5 — Hardening
- Full export, accessibility (VoiceOver, Dynamic Type), localization groundwork, battery and performance profiling of background sync, App Store privacy labels and HealthKit review notes.

## 8. Strava — what the terms say and my recommendation

I checked Strava's current **API Agreement** and **API Policy** (both effective **1 June 2026**):

- **API Policy §5.3** bars using Strava API materials or Strava Data, directly or indirectly, "in connection with the development, training, evaluation, or operation of any AI Application". This includes grounding, embedding and retrieval-augmented generation, and it covers data *derived* from Strava Data. The clause makes no exception for on-device processing.
- **API Policy §5.4** bars processing Strava Data for analytics or insight generation, and bars combining it with other data, even in aggregated or anonymized form.
- **API Agreement §1:** a user's Strava data may only be shown to that user.

Correlating workouts with sleep and heart data, and summarising them with an LLM, is exactly what §5.3 and §5.4 forbid. **I recommend not building the direct Strava integration.**

Workouts that the Strava app writes into Apple Health reach us as HealthKit data, not through Strava's API. In my reading the API terms don't govern them, but I'm not a lawyer. Before launch, either confirm this with counsel or exclude workouts whose HealthKit source is Strava from AI narratives (keeping them in the numbers). For Phase 1 I'll add a source filter so either choice is a one-line switch.

## 9. Testing strategy
- **Swift Testing** for the packages. `InsightEngine` and the `Narrative` validator aim for close to full branch coverage.
- Sync is tested against `FakeHealthDataSource`: insert, delete, anchor resume, and a crash between fetch and commit.
- Narrative is tested by validating recorded model outputs (golden files) and checking that the template renderer is deterministic.
- UI smoke tests (XCUITest) in Phase 5.

## 10. Tooling and CI

**Constraint you should know about:** this cloud session runs on Linux and has no Swift toolchain or Xcode. I can write the code but can't compile or run it here. I'll verify through **GitHub Actions macOS runners** (`macos-26`, Xcode 26) on every push. Phase 1 definition-of-done items 1–4 need you to run them on a physical device; I'll write a short manual test script for that. Note that macOS runner minutes on a private repo count against your Actions quota at a higher rate.

CI jobs:
- Build.
- Unit tests on the iOS simulator.
- `swift-format lint`.
- A guard script that fails on `URLSession`, `Network` framework imports, `print(`, `NSLog`, and any dependency not on the approved list.

## 11. Items needing your approval

1. **Dependencies:** GRDB.swift + SQLCipher (app runtime). Also **XcodeGen** (dev-only), so the Xcode project is generated from a `project.yml` I can write without Xcode. The alternative is a hand-written `.pbxproj`, which is fragile.
2. **CI:** using GitHub Actions macOS minutes as described in §10.
3. **Bundle ID and team:** for example `com.<you>.vivra`, plus your Apple Developer Team ID, needed for the HealthKit entitlement. A placeholder works until you sign builds.
4. **Writing back to HealthKit:** should in-app mood logs also be written to Apple Health as State of Mind, and drinks as water, caffeine or alcohol? I'd suggest yes, as an opt-in, so other apps benefit. It needs write permission.
5. **Strava:** confirm dropping the direct integration (§8).
6. **Phase 1 definition of done** (§7) as written.
