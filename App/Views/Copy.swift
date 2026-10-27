/// Shared user-facing text that must stay consistent across screens.
/// Localizable through the app's String Catalog.
enum Copy {
    static let disclaimer = String(
        localized: """
            Vivra is not a medical device and doesn't give medical advice. It shows patterns in your own data. \
            It can't tell you why they happen or what they mean for your health. If you have questions about \
            your health, talk to a healthcare professional.
            """)

    static let shortDisclaimer = String(
        localized: "Not medical advice. Vivra describes patterns in your data, not their causes.")

    static let professionalNote = String(
        localized: "If you have questions about this, consider talking with a healthcare professional.")

    static let drinkEstimates = String(
        localized: """
            A glass of water counts as 250 mL. Caffeine is estimated at 95 mg per cup of coffee and 47 mg per cup of \
            tea (USDA FoodData Central). A drink of alcohol counts as one standard drink.
            """)

    static let heartRecordingsNote = String(
        localized: """
            Vivra lists these exactly as Apple Health recorded them. It doesn't interpret them or use them in insights.
            """)

    static let feelingOffNote = String(
        localized: """
            Vivra can't tell why you feel a certain way. It shows things in your data that stood out today, and \
            patterns seen before.
            """)

    static let healthAccessHint =
        String(
            localized:
                "If you expected data here, check Vivra's access in Settings › Privacy & Security › Health › Vivra.")
}
