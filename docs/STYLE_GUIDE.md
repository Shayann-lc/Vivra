# Vivra writing style guide

This guide covers every sentence Vivra shows about someone's data: templates,
on-device model output, empty states and notes.

**The code is what enforces it.** `Packages/VivraCore/Sources/NarrativeCore/StyleGuide.swift`
holds the banned word lists and the model's instructions, and `NarrativeValidator`
rejects any model draft that breaks them. If you change this guide, change that file
in the same commit.

## Tone

- **Neutral and calm.** Describe the data; don't react to it.
- **Encouraging, never cheerleading.** Leave out "great job" and "well done". Praise
  turns into judgement as soon as the numbers go the other way.
- **Second person.** "You slept…", "Your resting heart rate…".
- **Plain words.** Use "heart rate variability (SDNN)", not "HRV" on its own the
  first time.

## Patterns, not causes

Vivra observes things that happen together. It never knows why.

| Write | Don't write |
|---|---|
| "On days after a night shorter than your median of 6h 45m, your resting heart rate had a median of 63 bpm, compared with 59 bpm after longer nights." | "Short sleep raises your resting heart rate." |
| "On nights after a workout day, you slept a median of 7h 30m." | "Exercise improves your sleep." |

Banned causal phrases include *because, causes, due to, leads to, results in, affects,
improves, worsens, boosts, thanks to, therefore, which means*. The full list is in
`StyleGuide.causalPhrases`.

Every pattern shows how many days it's based on and a confidence level (low, medium or
high).

## No judgement

There are no good or bad days, nights or weeks.

- Banned words include *bad, poor, better, worse, best, ideal, optimal, healthy,
  unhealthy, too much, too little, lazy, failed*.
- Describe a change neutrally: "compared with 61 bpm the week before", not
  "down to a better 58 bpm".
- When a streak breaks (Phase 3), say "Welcome back". Never mention a loss.

## No advice, no medicine

- Don't use imperatives about health. Avoid *should, must, need to, try to, make sure*.
- Vivra never diagnoses, names a condition or explains what a value means for health.
  Clinical words (*diagnosis, disease, disorder, abnormal, symptom, risk, dangerous,
  treatment, doctor, medical*) are banned in generated text.
- When a value is outside a bundled typical range, show exactly this and nothing more:
  > If you have questions about this, consider talking with a healthcare professional.
- The disclaimer appears in onboarding (must be acknowledged), in Settings and under
  every summary:
  > Vivra is not a medical device and doesn't give medical advice. It shows patterns in
  > your own data. It can't tell you why they happen or what they mean for your health.
  > If you have questions about your health, talk to a healthcare professional.

## Numbers

- Only numbers the insight engine calculated may appear. The model is given each finding
  as a sentence and may only reuse its numbers. It may also state the size of a reported
  difference, which the validator allows.
- Formats (from `FindingFormatter`):

  | Quantity | Format | Example |
  |---|---|---|
  | Duration | hours and minutes | 7h 5m |
  | Heart rate | whole bpm | 58 bpm |
  | HRV | whole ms | 42 ms |
  | VO2 max | one decimal | 41.3 mL/kg/min |
  | Workout time | whole minutes | 95 min |

## Empty states

Never imply that the person did something wrong. "No sleep recorded in the last 7 days"
is followed by where to check Health access. "You didn't track your sleep" is not
acceptable.

## Progress and reminders (Phase 3)

Progress rewards logging, never exercise, and never frames anything as a loss.
The research behind this is in `docs/UX_RESEARCH.md` §5.

- Say **run**, not "streak". Say **pause**, not "freeze".
- When someone returns after a gap, say **"Welcome back. Nice to see you."**
  Never mention what ended.
- Don't use loss language: *streak, lost, lose, broken, reset, fail, missed out,
  hurry, don't forget, before it's too late*. The full list is
  `ProgressCopy.lossPhrases`, and a test checks every progress and reminder string
  against it and against the banned terms above.
- Draw missed days as empty, neutral circles. Never use red or a cross.
- Reminders are an invitation ("if you'd like"), with no numbers, no health data
  and no run counts.
