import Foundation
import VivraModel

/// Made-up but plausible data for screenshots, UI tests and previews: 90 days
/// of sleep, heart, activity, workouts, body measurements and Quick Log
/// entries. Seeded, so the same inputs always give the same data. Never shown
/// to people: the app only loads it in Debug builds launched with
/// `-sample-data`.
///
/// It has a few built-in relationships, so the pattern search has something
/// to find: more sleep goes with higher heart rate variability and better
/// mood, and workout days go with more steps and a longer night after.
public struct SampleData: Sendable {
    /// One batch per synced type, in the order they should be applied.
    public let batches: [(type: HealthDataType, batch: ChangeBatch)]
    public let logs: [LogEntry]

    public static let source = SourceInfo(bundleIdentifier: "app.vivra.sample", name: "Sample Data")

    /// Data for the `days` days up to and including today. Nothing is later
    /// than `now`.
    public static func generate(now: Date, calendar: DayCalendar, days: Int = 90, seed: UInt64 = 2026)
        -> SampleData
    {
        var random = SampleRandom(seed: seed)
        var quantities: [QuantityKind: [QuantitySample]] = [:]
        var sleep: [SleepInterval] = []
        var workouts: [Workout] = []
        var logs: [LogEntry] = []

        func at(_ day: Day, hours: Double) -> Date {
            calendar.start(of: day).addingTimeInterval(hours * 3600)
        }
        func add(_ kind: QuantityKind, _ value: Double, start: Date, end: Date? = nil) {
            guard (end ?? start) <= now else { return }
            quantities[kind, default: []].append(
                QuantitySample(
                    id: random.uuid(), kind: kind, start: start, end: end ?? start, value: value, source: source)
            )
        }

        let today = calendar.day(now)
        var workedOutYesterday = false
        for offset in stride(from: days - 1, through: 0, by: -1) {
            let day = calendar.adding(days: -offset, to: today)
            let weekend = isWeekend(day, calendar: calendar)

            // The night that ends this morning.
            let asleepHours = 7.0 + random.normal() * 0.7 + (workedOutYesterday ? 0.4 : 0) + (weekend ? 0.5 : 0)
            let bedtime = at(day, hours: -1.0 + random.normal() * 0.5)
            // A watch saves the night after waking, so a night still in
            // progress at `now` isn't included at all.
            let intervals = night(from: bedtime, asleepHours: asleepHours, random: &random)
            if let end = intervals.last?.end, end <= now { sleep += intervals }

            add(
                .restingHeartRate, (58 - (asleepHours - 7) * 1.5 + random.normal() * 1.5).rounded(),
                start: at(day, hours: 8))
            add(
                .heartRateVariabilitySDNN, (48 + (asleepHours - 7) * 7 + random.normal() * 5).rounded(),
                start: at(day, hours: 7))
            add(.respiratoryRate, 14.5 + random.normal() * 0.4, start: at(day, hours: 4))

            let workout = random.uniform() < 0.4
            workedOutYesterday = workout
            let steps = max(1500, 7500 + random.normal() * 2200 + (weekend ? 2000 : 0) + (workout ? 3000 : 0))
            let exercise = max(5, 20 + random.normal() * 8 + (workout ? 35 : 0))
            let energy = max(150, 420 + random.normal() * 90 + (workout ? 320 : 0))
            if offset == 0 {
                // Today so far, in proportion to the waking hours gone by.
                let soFar = min(max((now.timeIntervalSince(at(day, hours: 7))) / (13 * 3600), 0), 1)
                if soFar > 0 {
                    add(.stepCount, (steps * soFar).rounded(), start: at(day, hours: 7), end: now)
                    add(.appleExerciseTime, (exercise * soFar).rounded(), start: at(day, hours: 7), end: now)
                    add(.activeEnergyBurned, (energy * soFar).rounded(), start: at(day, hours: 7), end: now)
                }
            } else {
                add(.stepCount, steps.rounded(), start: at(day, hours: 7), end: at(day, hours: 21))
                add(.appleExerciseTime, exercise.rounded(), start: at(day, hours: 7), end: at(day, hours: 21))
                add(.activeEnergyBurned, energy.rounded(), start: at(day, hours: 7), end: at(day, hours: 21))
            }

            if workout {
                let start = at(day, hours: 18 + random.uniform())
                let minutes = 30 + random.uniform() * 30
                let end = start.addingTimeInterval(minutes * 60)
                if end <= now {
                    let kind = workoutKinds[Int(random.uniform() * Double(workoutKinds.count))]
                    workouts.append(
                        Workout(
                            id: random.uuid(), activityType: kind.activityType, start: start, end: end,
                            duration: minutes * 60, activeEnergyKilocalories: (minutes * 9).rounded(),
                            distanceMeters: kind.metersPerMinute.map { ($0 * minutes).rounded() }, source: source)
                    )
                }
            }
            if offset % 7 == 3 { add(.vo2Max, 41.5 + random.normal() * 0.4, start: at(day, hours: 18)) }
            if offset % 3 == 0 { add(.bodyMass, 72.0 + random.normal() * 0.3, start: at(day, hours: 7.5)) }

            // Quick Log: most evenings, with mood following sleep.
            if random.uniform() < 0.85 {
                let evening = at(day, hours: 20.5)
                if evening <= now {
                    let mood = clampScale(3.3 + (asleepHours - 7) * 0.8 + random.normal() * 0.6)
                    logs.append(LogEntry(id: random.uuid(), kind: .mood, timestamp: evening, scale: mood))
                    logs.append(
                        LogEntry(
                            id: random.uuid(), kind: .energy, timestamp: evening,
                            scale: clampScale(3 + (asleepHours - 7) * 0.6 + random.normal() * 0.7)))
                    logs.append(
                        LogEntry(
                            id: random.uuid(), kind: .stress, timestamp: evening,
                            scale: clampScale(2.6 - (asleepHours - 7) * 0.4 + random.normal() * 0.8)))
                    let water = 4 + Int(random.uniform() * 4)
                    logs.append(
                        LogEntry(
                            id: random.uuid(), kind: .drink, timestamp: evening, drink: .water,
                            amount: Double(water) * Drink.water.amountPerServing))
                    if random.uniform() < 0.25 {
                        logs.append(
                            LogEntry(
                                id: random.uuid(), kind: .drink, timestamp: evening, drink: .alcohol,
                                amount: random.uniform() < 0.5 ? 1 : 2))
                    }
                }
            }
            let morning = at(day, hours: 8.5)
            if morning <= now {
                let cups = 1 + Int(random.uniform() * 2)
                logs.append(
                    LogEntry(
                        id: random.uuid(), kind: .drink, timestamp: morning, drink: .coffee,
                        amount: Double(cups) * Drink.coffee.amountPerServing))
            }
        }

        var batches: [(type: HealthDataType, batch: ChangeBatch)] = [
            (.sleep, ChangeBatch(sleepIntervals: sleep, newAnchor: Data(), hasMore: false)),
            (.workouts, ChangeBatch(workouts: workouts, newAnchor: Data(), hasMore: false)),
        ]
        for kind in QuantityKind.allCases {
            guard let samples = quantities[kind] else { continue }
            batches.append(
                (HealthDataType(kind), ChangeBatch(quantitySamples: samples, newAnchor: Data(), hasMore: false)))
        }
        return SampleData(batches: batches, logs: logs)
    }

    /// One night as Apple Watch records it: cycles of core, deep and REM
    /// sleep with a short wake, all asleep time adding up to `asleepHours`.
    private static func night(from bedtime: Date, asleepHours: Double, random: inout SampleRandom)
        -> [SleepInterval]
    {
        let asleep = asleepHours * 3600
        let pattern: [(SleepStage, Double)] = [
            (.core, 0.14), (.deep, 0.10), (.core, 0.12), (.rem, 0.08), (.core, 0.14), (.deep, 0.05),
            (.rem, 0.10), (.core, 0.15), (.rem, 0.12),
        ]
        var intervals: [SleepInterval] = []
        var start = bedtime
        for (index, (stage, share)) in pattern.enumerated() {
            let end = start.addingTimeInterval(asleep * share)
            intervals.append(SleepInterval(id: random.uuid(), stage: stage, start: start, end: end, source: source))
            start = end
            if index == 4 {
                let wakeEnd = start.addingTimeInterval(300 + random.uniform() * 600)
                intervals.append(
                    SleepInterval(id: random.uuid(), stage: .awake, start: start, end: wakeEnd, source: source))
                start = wakeEnd
            }
        }
        return intervals
    }

    private struct WorkoutKind {
        /// `HKWorkoutActivityType` raw values.
        let activityType: UInt
        let metersPerMinute: Double?
    }

    private static let workoutKinds = [
        WorkoutKind(activityType: 37, metersPerMinute: 170),  // running
        WorkoutKind(activityType: 13, metersPerMinute: 380),  // cycling
        WorkoutKind(activityType: 50, metersPerMinute: nil),  // strength training
    ]

    private static func isWeekend(_ day: Day, calendar: DayCalendar) -> Bool {
        let weekday = calendar.calendar.component(.weekday, from: calendar.start(of: day))
        return weekday == 1 || weekday == 7
    }

    private static func clampScale(_ value: Double) -> Int {
        min(max(Int(value.rounded()), LogEntry.scaleRange.lowerBound), LogEntry.scaleRange.upperBound)
    }
}

/// SplitMix64 (Steele et al., 2014), with the few draws the sample data
/// needs.
private struct SampleRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// In [0, 1).
    mutating func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }

    /// Standard normal, by Box–Muller.
    mutating func normal() -> Double {
        let u = max(uniform(), .leastNonzeroMagnitude)
        return (-2 * log(u)).squareRoot() * cos(2 * .pi * uniform())
    }

    mutating func uuid() -> UUID {
        let a = next()
        let b = next()
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8(truncatingIfNeeded: a >> (8 * i))
            bytes[8 + i] = UInt8(truncatingIfNeeded: b >> (8 * i))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40  // version 4
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // variant
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9],
                bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }
}
