# App Store submission notes

Draft answers for App Store Connect, and the decisions that remain with the owner.
Check them against Apple's current guidance when you submit, because Apple changes
these forms.

## 1. Privacy nutrition label

**Answer: Data Not Collected.**

Apple counts data as "collected" when it's transmitted off the device in a way that
the developer or a third party can access. Vivra:

- has no server, no analytics, no crash reporter and no ads, and makes no network
  calls (CI enforces this with `scripts/check-guards.sh`);
- keeps everything in an encrypted database on the iPhone;
- writes mood and drinks to Apple Health only when the person turns that on, and the
  data stays in their Health store;
- uses Apple Intelligence (Foundation Models) on device only;
- exports data only when the person taps **Export All Data**, to a destination they
  pick in the share sheet.

**Crash reports (owner, decided):** not declared. Vivra has no crash reporter. The only
crash data is what people choose to share with developers through Apple's own
diagnostics setting, which the app doesn't control. The label stays "Data Not
Collected"; recheck Apple's wording at submission in case it changes.

The privacy manifest (`App/Resources/PrivacyInfo.xcprivacy`) declares no tracking, no
collected data types, and `UserDefaults` access for reason `CA92.1`. Before
submitting, run **Product › Archive**, then **Generate Privacy Report** in the
Organizer, to confirm that the vendored GRDB and SQLCipher don't need further
required-reason entries.

## 2. HealthKit

Relevant App Review Guidelines: 2.5.1, 5.1.1, 5.1.2 and 5.1.3.

- **The interface says Vivra uses Apple Health.** Onboarding explains each permission
  group before the system sheet appears. The description and screenshots must say
  so too (see §4).
- **Purpose strings** are in `project.yml`:
  - `NSHealthShareUsageDescription`: what's read, and that it stays on the iPhone.
  - `NSHealthUpdateUsageDescription`: opt-in saving of mood and drinks.
- **Not used for advertising or data mining.** Health data isn't stored in iCloud,
  and nothing leaves the device.
- **A privacy policy URL is required** for every app, and especially for HealthKit
  apps. **Owner to provide.** A short page is enough, saying that Vivra collects
  nothing, stores data only on the device, encrypted, and offers export and delete.
- **Medical claims (1.4.1):** Vivra makes none. It describes patterns in the person's
  own data, uses non-causal language (`docs/STYLE_GUIDE.md`, enforced by
  `StyleGuide.swift`), and shows a "not medical advice" disclaimer during onboarding,
  on Today, Insights and metric detail, and in Settings › About. ECG records are listed exactly as
  Health recorded them and are never interpreted.
- **Reference norms** cite their primary sources and licences (`docs/NORMS.md`). The
  App Store build contains no FRIEND data (PLAN decision 10).

## 3. Review notes (paste into App Review Information)

> Vivra is an on-device lifestyle journal. It reads Apple Health data the user allows
> and shows trends and patterns. It has no account, no server and no network access;
> all data is encrypted on the device.
>
> To review without Health data: complete onboarding (you can tap "Not Now" for every
> permission), then open the Log tab and save a mood, energy level or drink. That
> fills the Today and Progress tabs. Reports in Insights need about a week of data;
> with less, they say there isn't enough data yet, which is expected.
>
> With an Apple Watch-paired device: allow the permissions, and Today shows sleep,
> heart and activity cards from the last 90 days within a minute.
>
> Apple Intelligence summaries appear on supported devices with Apple Intelligence
> turned on. Otherwise Vivra writes the same summaries from templates.
>
> Settings › Export All Data shares a zip of the user's data; Settings › Delete All
> Vivra Data removes everything, including the encryption key.
>
> Vivra is not a medical device and doesn't give medical advice.

## 4. Description and age rating

- **Description disclaimer** (last paragraph of the description):
  "Vivra is not a medical device and doesn't provide medical advice. It describes
  patterns in your own data, not their causes. Talk to a healthcare professional
  about your health. Vivra works with Apple Health."
- **Age rating questionnaire:**
  - Medical or treatment information: **None.** Vivra gives no diagnosis or treatment
    information.
  - Alcohol, tobacco or drug use or references: people can log alcoholic drinks, and
    Vivra reads alcohol intake from Health. **Owner to decide** whether this counts as
    "Infrequent/Mild" references. It affects the rating.
  - Everything else: None.
  - Note that the reference norms use adult data, and the birth year picker only
    offers ages 18 and over.

## 5. Export compliance (owner's decision)

Vivra encrypts its database with SQLCipher (AES-256), a non-Apple library, in
addition to iOS Data Protection. It uses encryption only to protect the person's own
data at rest on the device. It doesn't send encrypted data anywhere, and has no
networking.

App Store Connect asks whether the app uses encryption and whether it qualifies for
an exemption. Encryption used only to protect data at rest on the device is commonly
treated as exempt under the US Export Administration Regulations (Category 5 Part 2,
Note 4 and the mass-market provisions). This is a legal determination, so **the owner
needs to decide, with advice if needed.**

Once decided, add `ITSAppUsesNonExemptEncryption` (`NO` if exempt) to the app's
Info.plist keys in `project.yml`, so each upload stops asking. I couldn't confirm from
this environment which crypto provider SQLCipher.swift 4.19.0 links on Apple
platforms (CommonCrypto or its own), so check Zetetic's notes for that version if
your adviser asks.

## 6. Before the first submission

- [ ] Real bundle ID, team and widget App ID in `Config/Local.xcconfig`.
- [ ] HealthKit capability on the App ID, with background delivery.
- [ ] App icon (the asset catalog name is empty for now: `ASSETCATALOG_COMPILER_APPICON_NAME`).
- [ ] Privacy policy URL.
- [ ] Export-compliance answer and plist key.
- [ ] The device steps in `docs/DEVICE_TEST.md` (Phases 1–5) pass.
- [ ] The profiling checklist in `docs/PERFORMANCE.md` has been run.
