import Foundation
import HealthKit
import NarrativeCore
import VivraModel

enum Formatting {
    static func weekday(_ day: Day, calendar: Calendar = .autoupdatingCurrent) -> String {
        let date = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day)) ?? .now
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    static func shortDate(_ day: Day, calendar: Calendar = .autoupdatingCurrent) -> String {
        let date = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day)) ?? .now
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    static func dayRange(_ start: Day, _ end: Day, calendar: Calendar = .autoupdatingCurrent) -> String {
        func date(_ day: Day) -> Date {
            calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day)) ?? .now
        }
        return (date(start)..<date(end)).formatted(.interval.month(.abbreviated).day())
    }

    static func duration(_ seconds: TimeInterval) -> String {
        FindingFormatter.duration(seconds)
    }

    /// Apple Health's own wording for each ECG classification.
    static func ecgClassification(_ classification: ECGRecord.Classification) -> String {
        switch classification {
        case .sinusRhythm: "Sinus Rhythm"
        case .atrialFibrillation: "Atrial Fibrillation"
        case .inconclusiveLowHeartRate: "Low Heart Rate"
        case .inconclusiveHighHeartRate: "High Heart Rate"
        case .inconclusivePoorReading: "Poor Recording"
        case .inconclusiveOther: "Inconclusive"
        case .notSet, .unrecognized: "Not Classified"
        }
    }

    static func workoutName(_ rawValue: UInt) -> String {
        switch HKWorkoutActivityType(rawValue: rawValue) {
        case .running: "Running"
        case .walking: "Walking"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .hiking: "Hiking"
        case .yoga: "Yoga"
        case .pilates: "Pilates"
        case .rowing: "Rowing"
        case .elliptical: "Elliptical"
        case .functionalStrengthTraining, .traditionalStrengthTraining: "Strength Training"
        case .highIntensityIntervalTraining: "HIIT"
        case .coreTraining: "Core Training"
        case .cardioDance, .socialDance: "Dance"
        case .mixedCardio: "Cardio"
        case .cooldown: "Cooldown"
        default: "Workout"
        }
    }
}
