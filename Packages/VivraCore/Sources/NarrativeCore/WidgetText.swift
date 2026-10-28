/// What the Daily Summary widget shows: the headline and the first two
/// sentences of a summary. The app and the evals both use this, so they
/// agree on what the widget says.
public enum WidgetText {
    public static let sentenceCount = 2

    public static func sentences(from draft: NarrativeDraft) -> [String] {
        Array(draft.bullets.prefix(sentenceCount).map(\.text))
    }

    public static func make(from draft: NarrativeDraft) -> String {
        ([draft.headline] + sentences(from: draft)).joined(separator: "\n")
    }
}
