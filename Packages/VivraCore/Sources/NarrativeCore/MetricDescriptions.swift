import InsightEngine

/// What each metric is and where it comes from, in plain words. Never what a
/// value means for health (docs/STYLE_GUIDE.md).
public enum MetricDescriptions {
    public static func title(_ metric: Metric) -> String {
        let noun = MetricWords.noun(metric)
        return noun.prefix(1).uppercased() + noun.dropFirst()
    }

    public static func description(_ metric: Metric) -> String {
        switch metric {
        case .sleepDuration:
            "Time asleep for the night that ended that morning, from the device that recorded sleep stages, "
                + "or otherwise the one that recorded the most sleep."
        case .restingHeartRate:
            "Your heart rate while you're still and relaxed. Apple Watch estimates it about once a day."
        case .heartRateVariability:
            "The variation in time between heartbeats (SDNN), measured by Apple Watch, mostly during sleep. "
                + "It varies a lot from person to person, so your own usual range is the useful comparison."
        case .walkingHeartRateAverage:
            "Your average heart rate while walking, estimated by Apple Watch."
        case .vo2Max:
            "Apple Watch's estimate of cardio fitness from outdoor walks, runs and hikes."
        case .workoutMinutes, .workoutCount:
            "Workouts recorded in Apple Health by any app or device."
        case .steps:
            "Steps for the day. When iPhone and Apple Watch both count, Vivra uses whichever counted more, "
                + "so steps aren't counted twice."
        case .activeEnergy:
            "Energy burned through movement, from iPhone or Apple Watch."
        case .exerciseMinutes:
            "Minutes of brisk movement, as counted by Apple Watch."
        case .distance:
            "Walking and running distance from iPhone or Apple Watch."
        case .standHours:
            "Hours in which Apple Watch noticed you standing and moving for at least a minute."
        case .mindfulMinutes:
            "Time in mindfulness sessions saved to Apple Health."
        case .mood:
            "Your mood on a 1–5 scale, from Quick Log and from State of Mind entries in Apple Health."
        case .energyLevel:
            "How energetic you felt, on a 1–5 scale, from Quick Log."
        case .stressLevel:
            "How stressed you felt, on a 1–5 scale, from Quick Log."
        case .dietaryEnergy, .protein, .carbohydrates, .fat:
            "What food-tracking apps saved to Apple Health that day."
        case .water:
            "Water from Quick Log and from apps that save to Apple Health."
        case .caffeine:
            "Caffeine from Quick Log (estimated per cup) and from apps that save to Apple Health."
        case .alcohol:
            "Standard drinks from Quick Log and from apps that save to Apple Health."
        case .weight, .bodyFat:
            "Measurements saved to Apple Health by a scale or entered by hand."
        case .respiratoryRate:
            "Breaths per minute, measured by Apple Watch during sleep."
        case .bloodOxygen:
            "Blood oxygen readings from Apple Watch."
        case .wristTemperature:
            "Sleeping wrist temperature from Apple Watch."
        }
    }
}
