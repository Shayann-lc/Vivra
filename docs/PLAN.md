# Vivra — Architecture and Phased Plan

Status: **draft, awaiting owner approval.** Nothing is implemented until this is approved.

## 1. Decisions already made

| # | Decision | Answer |
|---|----------|--------|
| 1 | Leaderboard | **Dropped from v1.** Nothing about it is built. Gamification state is modelled so a leaderboard can be added later without a migration. |
| 2 | Apple Watch companion app | **Not in v1.** Watch data still arrives through HealthKit. |
| 3 | Minimum iOS | **iOS 26.** Foundation Models and State of Mind are both available. |
| 4 | Branching | Commit straight to `main`. |
| 5 | Direct Strava API integration | **Recommend not building it.** See §8. Workouts that Strava writes to Apple Health are still read through HealthKit. |

## 2. Principles, restated as engineering rules

- **No network code**, apart from the system frameworks Apple runs on its own (HealthKit, Foundation Models). There is no `URLSession` use in v1. CI fails if anyone adds it (see §10).
- **No third-party SDKs** that collect data: no analytics, crash reporters or ads. Crash data comes only from Apple's opt-in diagnostics.
- **The LLM never produces a number.** The Swift insight engine computes every figure. The model only words the findings it is given, and its output is checked against them (see §6.4).
- **No health values in logs.** Logging goes through one `Log` wrapper that only accepts values marked as safe (counts, durations, error codes). Anything else is logged with `privacy: .private`.
- **Injected clocks and calendars.** No `Date()` or `Calendar.current` calls inside engine or sync code. Tests run with a fixed clock, time zone and locale.

## 3. Architecture

```
Vivra.xcodeproj  (app target, iOS 26)
└── VivraApp                 SwiftUI app shell, navigation, app lock
Packages/ (local Swift packages; everything testable lives here)
├── VivraModel               Value types: Sample, SleepSession, Workout, LogEntry, Finding, …
├── VivraStore               Encrypted database, migrations, repositories
├── HealthSync               HealthKit wrapper: permissions, anchored queries, background delivery
├── InsightEngine            Pure Swift statistics. No Apple frameworks beyond Foundation
├── Narrative                Foundation Models prompts, style guide, output validator, template fallback
├── Gamification             (Phase 3) streaks, XP, goals, achievements
├── Norms                    (Phase 4) bundled reference norms with citations
└── VivraUI                  Reusable SwiftUI views and Swift Charts components
```

How the pieces depend on each other:
`VivraApp → VivraUI → {Narrative, InsightEngine, HealthSync, VivraStore} → VivraModel`.
`InsightEngine` depends only on `VivraModel`. That keeps it deterministic and quick to unit test.

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
- If you approve, I'll confirm exactly how SQLCipher is wired in (GRDB's SwiftPM SQLCipher support versus a pinned fork) in a Phase 0 spike before relying on it.
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
- **Correlations:** Spearman's ρ is the default, because it handles outliers and non-normal data. Each pair records n, ρ and a 95% confidence interval (Fisher z).
- **Lagged effects:** the same calculation applied to day *t* → day *t+1* pairs, for example alcohol to next-night HRV, or late workout to sleep latency.
- **Group differences:** for example, sleep under 6 h versus 6 h or more, compared on next-day resting HR. The result is a difference of medians with a bootstrap confidence interval using a fixed seed, so it is deterministic.
- **Gates before anything is shown to the user:**
  - n ≥ 14 paired days, and n ≥ 7 in each group for group differences.
  - |ρ| ≥ 0.3 or an effect above a per-metric minimum.
  - Benjamini–Hochberg false-discovery control across all the pairs tested in a report.
- **Confidence levels:** low, medium or high, based on n, the width of the confidence interval and how stable the result stays across the window.
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
- Spike: GRDB with SQLCipher opens, encrypts and migrates on a device.
- **Done when:** CI is green on `main`, and an empty app launches on a simulator.

### Phase 1 — The deliverable you specified
- Onboarding: what Vivra is, the disclaimer (must be acknowledged), grouped HealthKit permission requests.
- HealthSync for **sleep** (stages, time in bed), **heart** (HR, resting HR, HRV SDNN, walking HR average, VO2 max) and **workouts** (type, duration, energy, distance; no routes yet). Anchored queries and background delivery.
- Encrypted store with migrations.
- Dashboard: a card per data family for the last 7 days (sleep duration and stages, resting HR and HRV trend, workouts list) using Swift Charts.
- Weekly summary: Phase 1 engine subset (weekly averages, change from the previous week, one or two simple lagged comparisons when the gates pass) → Foundation Models narrative → validator → template fallback.
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
- Remaining HealthKit types:
  - Activity: steps, energy, exercise minutes, stand hours, distance, workout routes.
  - State of Mind and mindful minutes.
  - Nutrition and hydration, including caffeine and alcohol.
  - Body: weight, body fat, respiratory rate, SpO₂, wrist temperature.
  - ECG and irregular-rhythm events, listed only.
- Quick logging for mood, energy, stress, meals, drinks and notes. Target **under 10 seconds**: one tap from the Home Screen widget, Control Center or the Lock Screen through App Intents, then a single screen of chips and sliders.
- Full insight engine: correlations, lagged effects, trends, anomalies, confidence levels.
- Daily check-in report.

### Phase 3 — Gamification (rewards logging, not exercise)
- XP for logging only, a daily goal (default: one check-in), streaks with earned freezes (one per 7-day streak, up to two held), and achievements for consistency and exploring the app.
- Gentle local notifications at a time the user chooses, at most once a day, with copy from the style guide. There is no streak-loss alarm.
- When a streak breaks, the UI shows "Welcome back", never a loss message.

### Phase 4 — Deeper reports and reference norms
- Monthly deep-dive, and on-demand "Why did I feel off today?". The question goes to the engine first (today's anomalies and recent lagged findings), and the model only words the result.
- Age and sex comparisons from a bundled, versioned `norms.json`. Every row carries a citation that appears in the UI. Candidate sources are listed below, and licensing must be checked before any table is bundled:
  - VO2 max: FRIEND registry (Kaminsky et al., *Mayo Clin Proc* 2015, and later updates).
  - Resting HR: NHANES-based percentiles (Ostchega et al., NHSR 2011).
  - Sleep duration: AASM/SRS consensus (Watson et al., 2015) and NSF recommendations.
  - **Not ACSM tables:** they are copyrighted, so they need permission or must be avoided.

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
