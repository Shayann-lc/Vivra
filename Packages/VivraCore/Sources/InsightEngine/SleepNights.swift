import Foundation
import VivraModel

/// One night of sleep, attributed to the day the person woke up.
public struct SleepNight: Codable, Sendable, Equatable {
    public let wakeDay: Day
    public let source: SourceInfo
    /// Total time asleep (all asleep stages, overlaps merged).
    public let asleep: TimeInterval
    /// Time in bed, when the source records it.
    public let inBed: TimeInterval?
    /// Time per stage (overlaps within a stage merged).
    public let stages: [SleepStage: TimeInterval]
}

/// Assembles nights from raw sleep intervals.
public enum SleepNightBuilder {
    /// Sleep ending at or after 18:00 on day D−1 and before 18:00 on day D
    /// belongs to wake day D. That keeps a night that starts before midnight together
    /// and counts an afternoon nap towards the same day.
    static let dayBoundaryHour = 18

    public static func nights(from intervals: [SleepInterval], calendar: DayCalendar) -> [SleepNight] {
        var byDay: [Day: [SleepInterval]] = [:]
        for interval in intervals where interval.end > interval.start {
            byDay[wakeDay(for: interval.end, calendar: calendar), default: []].append(interval)
        }
        return byDay.keys.sorted().compactMap { day in
            night(for: day, intervals: byDay[day]!)
        }
    }

    static func wakeDay(for end: Date, calendar: DayCalendar) -> Day {
        // Shift so the boundary lands on midnight, then take the next day.
        let shifted = calendar.adding(hours: 24 - dayBoundaryHour, to: end)
        return calendar.day(shifted)
    }

    /// Picks one source per night, deterministically: a source with sleep
    /// stages beats one without (stages come from a worn device), then more
    /// time asleep, then the bundle identifier.
    private static func night(for day: Day, intervals: [SleepInterval]) -> SleepNight? {
        let bySource = Dictionary(grouping: intervals, by: \.source)
        let ranked = bySource.map { source, intervals in
            (
                source: source,
                intervals: intervals,
                staged: intervals.contains { $0.stage.isStaged },
                asleep: mergedDuration(intervals.filter { $0.stage.isAsleep })
            )
        }
        .sorted { lhs, rhs in
            if lhs.staged != rhs.staged { return lhs.staged }
            if lhs.asleep != rhs.asleep { return lhs.asleep > rhs.asleep }
            return lhs.source.bundleIdentifier < rhs.source.bundleIdentifier
        }
        guard let best = ranked.first, best.asleep > 0 else { return nil }

        var stages: [SleepStage: TimeInterval] = [:]
        for stage in SleepStage.allCases {
            let duration = mergedDuration(best.intervals.filter { $0.stage == stage })
            if duration > 0 { stages[stage] = duration }
        }
        return SleepNight(
            wakeDay: day,
            source: best.source,
            asleep: best.asleep,
            inBed: stages[.inBed],
            stages: stages
        )
    }

    /// Total length of the union of intervals.
    static func mergedDuration(_ intervals: [SleepInterval]) -> TimeInterval {
        let sorted = intervals.map { ($0.start, $0.end) }.sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var current: (start: Date, end: Date)?
        for (start, end) in sorted {
            if let open = current, start <= open.end {
                current = (open.start, max(open.end, end))
            } else {
                if let open = current { total += open.end.timeIntervalSince(open.start) }
                current = (start, end)
            }
        }
        if let open = current { total += open.end.timeIntervalSince(open.start) }
        return total
    }
}
