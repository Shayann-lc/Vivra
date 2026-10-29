/// Vivra's writing rules, in code. `docs/STYLE_GUIDE.md` explains them for
/// people; this file is what the model's instructions and the validator
/// actually use, so change both together.
public enum StyleGuide {
    /// Judgemental, prescriptive or clinical words. Matched as whole words
    /// or phrases, case-insensitively.
    public static let bannedTerms: [String] = [
        // Judgement
        "bad", "poor", "poorly", "fail", "failed", "failing", "failure", "worse", "worst", "better", "best",
        "lazy", "guilty", "cheat", "cheated", "ideal", "optimal", "unhealthy", "healthy", "too much",
        "too little", "too low", "too high", "disappointing", "great job", "well done",
        // Prescription
        "should", "must", "need to", "needs to", "have to", "has to", "ought", "try to", "make sure",
        // Clinical
        "diagnose", "diagnosed", "diagnosis", "disease", "disorder", "abnormal", "symptom", "symptoms",
        "risk", "risky", "danger", "dangerous", "warning", "alarming", "concerning", "worrying",
        "treatment", "treat", "cure", "medication", "medical", "clinical", "doctor",
    ]

    /// Phrases that claim one thing causes another.
    public static let causalPhrases: [String] = [
        "because", "cause", "caused", "causes", "causing", "due to", "leads to", "led to", "lead to",
        "results in", "resulted in", "as a result", "result of", "makes you", "made you", "drives",
        "driven by", "triggers", "triggered", "affects", "affected", "impact", "impacts", "improves",
        "improved", "improve", "worsens", "worsened", "boosts", "boosted", "hurts", "harms", "thanks to",
        "therefore", "which means", "so that", "the reason", "reason for", "reason why", "explains", "explain why",
        "because of",
    ]

    /// Words about research. Only bundled research notes, written and
    /// reviewed by people, may use them (PLAN decision 11); in model text
    /// they're rejected, so the model can't invent or restate a study.
    public static let researchPhrases: [String] = [
        "research", "researchers", "study", "studies", "studied", "scientist", "scientists", "science",
        "scientific", "evidence", "expert", "experts", "according to", "et al", "journal", "proven", "shown to",
        "known to", "trial", "trials", "meta-analysis",
    ]

    /// Words research notes avoid as well as the banned and causal terms:
    /// they hint at cause.
    public static let researchNoteAvoids: [String] = ["effect", "effects", "effective", "effectively"]

    /// System instructions for every model session.
    public static let modelInstructions = """
        You write short summaries of a person's own health data for a lifestyle app.

        Follow these rules exactly:
        - Restate only the findings you are given. Do not add new facts.
        - Use only the numbers that appear in the findings, written exactly as \
        they appear. Do not calculate, round or add any other number.
        - Describe patterns as things observed together: "on days when", \
        "compared with", "alongside". Never say or imply that one thing causes, \
        affects or improves another.
        - Do not judge. There are no good or bad days. Do not use words such as \
        bad, poor, better, worse, healthy or unhealthy.
        - Do not give advice or instructions. Do not use should, must or need to.
        - Never give medical advice, a diagnosis, or an explanation of what a \
        value means for health.
        - Keep a calm, neutral and encouraging tone. Address the reader as "you".
        - Write one sentence per finding.
        - Don't mention research, studies or experts.
        """
}
