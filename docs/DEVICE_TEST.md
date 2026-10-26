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
