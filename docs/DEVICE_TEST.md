# Phase 1 device test script

These are the steps for the Phase 1 definition-of-done items that CI can't check
(PLAN §7). Run them on a physical iPhone with iOS 26 and at least a few weeks of
Apple Health data (ideally from an Apple Watch).

## Setup

1. `cp Config/Local.xcconfig.example Config/Local.xcconfig` and set
   `VIVRA_BUNDLE_ID` and `DEVELOPMENT_TEAM`. The App ID needs the **HealthKit**
   capability, with background delivery, and the **Data Protection** capability set
   to Complete.
2. `xcodegen generate && open Vivra.xcodeproj`, then run the **Vivra** scheme on
   the device.

## 1. Fresh install, permissions, 90-day sync, dashboard

1. Delete Vivra from the phone if it's installed, then run from Xcode.
2. Onboarding shows Welcome, then the disclaimer. **I Understand** is the only way
   forward.
3. Sleep, Heart and Workouts each show their own explanation screen, and **Allow
   Access** opens the Health sheet for that group only.
4. On **Go to Dashboard**, the Sleep, Heart and Workouts cards fill in within about a
   minute.
5. ✅ The data matches the Health app for the last 7 days: the most recent night's
   sleep, the resting heart rate trend, and the list of workouts.

## 2. Incremental sync, with no duplicates

1. Record a short workout on the Watch (or add one in Health › Browse › Activity ›
   Workouts › Add Data).
2. Bring Vivra to the foreground, or pull to refresh. ✅ The workout appears once.
3. Pull to refresh twice more. ✅ It still appears once.
4. Delete that workout in the Health app, then refresh Vivra. ✅ It disappears.
5. Background delivery: lock the phone, add another workout from the Watch, wait a few
   minutes, then unlock and open Vivra without pulling to refresh. ✅ The workout is
   already there.

## 3. The database can't be read without the key

1. In Xcode, open **Window › Devices and Simulators**, select the phone, choose
   Vivra, then **Download Container…**.
2. In the container: `AppData/Library/Application Support/Database/vivra.sqlite`.
3. `sqlite3 vivra.sqlite ".tables"` ✅ fails with "file is not a database".
4. `head -c 16 vivra.sqlite | xxd` ✅ shows no `SQLite format 3` header.

## 4. Weekly summary, with and without Apple Intelligence

1. On an Apple Intelligence iPhone with it turned on: Summary › **Create Summary**.
   ✅ The footer says "Written on this iPhone by Apple Intelligence". Every number in it
   also appears on the dashboard or in the template wording.
2. Turn Apple Intelligence off (Settings › Apple Intelligence & Siri) and create a new
   summary. ✅ The footer says "Written from Vivra's templates".
3. ✅ Neither summary uses causal or judgemental language (see `docs/STYLE_GUIDE.md`),
   and the disclaimer appears under both.

## 6. Delete everything

1. Settings › **Delete All Vivra Data** › Delete Everything.
2. ✅ The "All Vivra data has been deleted" screen shows, with no warning about data
   that couldn't be confirmed.
3. Download the container again. ✅ `Application Support/Database` doesn't exist, and
   `Library/Preferences/<bundle id>.plist` is absent or has no Vivra keys.
4. **Start Again** opens onboarding.

Item 5 (unit tests and green CI) is checked by CI.

---

# Phase 2 device steps

These cover the Phase 2 definition-of-done items that CI can't check (PLAN §7, Phase 2).

## Setup

- The App ID also needs the widget extension's bundle ID (`<bundle id>.widgets`).
- Use a phone with some activity, nutrition (any food-logging app), State of Mind and
  body data in Apple Health, if possible.

## A. New data types and permissions

1. **On a Phase 1 install:** update the app. ✅ The dashboard shows "More Health data
   available". **Review Access** lists Heart, Activity, State of Mind, Nutrition and
   Body. Allow each one; when the last is answered, the sheet closes.
2. **On a fresh install:** ✅ onboarding asks for all seven groups in order.
3. ✅ The Activity card shows steps. Body shows the latest weight if you have one.
   Today shows anything logged.
4. If the phone has ECG recordings, Heart › **Heart recordings from Apple Health**
   ✅ lists them with Apple's classification wording, the note that Vivra doesn't
   interpret them, and the professional note.

## B. Quick Log under 10 seconds

1. Log tab: tap mood **4**, press **+** once on Coffee, then **Save**. Time it
   (✅ under 10 s). The entry appears under **Logged today**, and Dashboard › Today
   shows Mood 4 out of 5 and Caffeine 95 mg.
2. Swipe to delete the coffee. ✅ It disappears from both places.
3. Entry points. Each should open Vivra on the Log tab:
   - Add the **Quick Log** widget to the Home Screen and tap it.
   - Add the **Vivra Quick Log** control in Control Center and tap it.
   - Say or run "Quick log in Vivra" in Shortcuts or Siri.
   - Add the Lock Screen widget and tap it.

## C. Write-back

1. Settings › **Save Mood and Drinks to Health** › allow in the sheet.
2. Log mood 2 and 1 coffee. ✅ The Health app shows a State of Mind entry from Vivra
   (unpleasant side) and 95 mg caffeine from Vivra.
3. ✅ Dashboard › Today shows caffeine 95 mg, not 190 (no double counting after sync).
4. Delete both entries in Vivra. ✅ They're gone from the Health app too.

## D. Daily check-in and patterns

1. Insights › **Create Check-in** on an Apple Intelligence device. ✅ It's written by
   Apple Intelligence. Then turn Apple Intelligence off and create another. ✅ It's
   written from templates. Both use only numbers that match the dashboard, and
   neither uses causal or judgemental words.
2. Insights › **Patterns**. ✅ Each line names its days and confidence, with
   "patterns, not causes" in the footer. With too little data it says "No patterns
   yet".
