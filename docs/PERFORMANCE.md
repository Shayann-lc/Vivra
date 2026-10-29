# Battery and sync performance

A profiling checklist to run on a real iPhone, with an Apple Watch paired and at least
a few weeks of Health data. The simulator has no background delivery and very little
data, so its numbers mean nothing here. The ✅ thresholds are proposed targets, not
measured baselines; adjust them after the first run.

## What's in the code

- **Signposts.** `Log.measure(_:)` in `VivraLogging` wraps work in an `OSSignposter`
  interval (subsystem `app.vivra`). The names are `StaticString`s, like every log
  message, so no health values reach Instruments. The intervals are:

  | Category | Interval | Covers |
  |---|---|---|
  | `sync` | Sync all | A full sync of every type |
  | `sync` | Sync type | One type's anchored fetch and database writes |
  | `app` | Refresh | Dashboard, today's logs, analysis and progress reload |
  | `insights` | Patterns and glance | Pattern search and the Today glance |
  | `insights` | Build report | One report's statistics |
  | `narrative` | Compose summary | The on-device model draft, checks and fallback |

- **Background delivery frequency** (`HealthKitDataSource.frequency(for:)`):
  - **Immediate:** sleep, workouts, State of Mind, ECG, irregular rhythm, mindful
    minutes.
  - **Daily:** raw heart rate (the highest-volume type; no screen shows it raw), VO2
    max, weight, body fat, wrist temperature.
  - **Hourly:** everything else.

  Opening the app always syncs every type, whatever the frequency.
- **Coalesced refreshes.** Each background delivery syncs its own type right away,
  because HealthKit waits for that before it lets the app suspend. The dashboard
  refresh that follows waits 2 seconds (`AppModel.refreshCoalescingDelay`), and any
  newer delivery restarts the wait, so a burst of types costs one refresh.

## Checklist

### 1. First sync (90 days)

1. Delete Vivra, reinstall, and allow every permission group.
2. In Instruments, choose the **Time Profiler** template and add the **os_signpost**
   instrument filtered to subsystem `app.vivra`. Record from launch.
3. ✅ **Sync all** finishes in under a minute with a year of Watch data, and the
   interface stays responsive while it runs (no hitches in the **Hangs** track).
4. Note the slowest **Sync type** intervals. Heart rate is expected to be the
   largest.

### 2. Steady-state battery

1. Use the phone normally for 24 hours with Vivra installed and onboarded, but don't
   open it.
2. Settings › Battery › last 24 hours. ✅ Vivra's background activity is under 1%.
3. If it's higher, record a **Background Tasks** trace or use Xcode › Debug › Simulate
   Background Fetch on device, and check which types wake the app most often.

### 3. Bursts of deliveries

1. Finish a workout on the Watch (it writes workouts, heart rate, energy and distance
   together).
2. With Console.app streaming `subsystem:app.vivra`, ✅ there are several "Sync type"
   intervals but only one **Refresh** shortly after.

### 4. Reports

1. With 90 days of data, create each report kind in Insights.
2. ✅ **Build report** takes under 200 ms. **Compose summary** dominates when Apple
   Intelligence is on (expect a few seconds), and the button shows progress meanwhile.

### 5. Export

1. Settings › **Export All Data** with a year of data.
2. ✅ The share sheet opens within a few seconds, and memory stays under 300 MB in
   the Xcode memory gauge. The export loads every table into memory, so this is the
   point to watch as data grows.

### 6. Connections (Phase 7)

1. With 90 days of data, pull to refresh Insights › Connections while recording the
   `insights` category.
2. ✅ Building Connections adds under **150 ms** to the **Patterns and glance**
   interval on a recent iPhone. Opening a connection's detail feels instant.

Record results and the device model here when you run it.
