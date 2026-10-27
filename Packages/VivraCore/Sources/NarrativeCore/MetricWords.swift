import InsightEngine

/// How each metric is named in sentences.
enum MetricWords {
    static func noun(_ metric: Metric) -> String {
        switch metric {
        case .sleepDuration: "sleep"
        case .restingHeartRate: "resting heart rate"
        case .heartRateVariability: "heart rate variability (SDNN)"
        case .walkingHeartRateAverage: "walking heart rate"
        case .vo2Max: "VO2 max estimate"
        case .workoutMinutes: "workout time"
        case .workoutCount: "workout count"
        case .steps: "step count"
        case .activeEnergy: "active energy"
        case .exerciseMinutes: "exercise time"
        case .distance: "walking and running distance"
        case .standHours: "stand hours"
        case .mindfulMinutes: "mindful minutes"
        case .mood: "mood"
        case .energyLevel: "energy level"
        case .stressLevel: "stress level"
        case .dietaryEnergy: "food energy"
        case .protein: "protein"
        case .carbohydrates: "carbohydrates"
        case .fat: "fat"
        case .water: "water"
        case .caffeine: "caffeine"
        case .alcohol: "alcohol"
        case .weight: "weight"
        case .bodyFat: "body fat"
        case .respiratoryRate: "respiratory rate"
        case .bloodOxygen: "blood oxygen"
        case .wristTemperature: "sleeping wrist temperature"
        }
    }

    /// Daily totals (as opposed to readings averaged over the day).
    static func isDailyTotal(_ metric: Metric) -> Bool {
        switch metric {
        case .steps, .activeEnergy, .exerciseMinutes, .distance, .standHours, .mindfulMinutes, .dietaryEnergy,
            .protein, .carbohydrates, .fat, .water, .caffeine, .alcohol, .workoutMinutes, .workoutCount:
            true
        default:
            false
        }
    }

    /// What follows a formatted amount: "180 mg" + " of caffeine". Empty
    /// when the unit already names the thing ("8,000 steps").
    static func amountSuffix(_ metric: Metric) -> String {
        switch metric {
        case .steps, .standHours, .workoutCount: ""
        case .exerciseMinutes: " of exercise"
        case .mindfulMinutes: " of mindfulness"
        case .distance: " walking and running"
        case .activeEnergy: " of active energy"
        case .dietaryEnergy: " of food energy"
        default: " of \(noun(metric))"
        }
    }

    static func isScale(_ metric: Metric) -> Bool {
        metric.unit == .scale
    }

    static func when(_ daysAgo: Int) -> String {
        daysAgo == 0 ? "today" : "yesterday"
    }
}
