# Evals for AI-written text

Every summary the on-device model writes goes through `SummaryComposer`. That covers
the daily check-in, the weekly and monthly summaries, and "Why do I feel off today?".
The evals score those summaries against fixed cases (PLAN Phase 6).

- **Cases** (`NarrativeEvals.EvalCorpus`): there are 60.
  - 44 come from seeded sample data, run through the real report builders.
  - 16 are written by hand, so every finding type, rises and falls, extremes and
    empty reports are covered.
- **Scorers** (`NarrativeEvals.EvalScoring`):
  - validator: grounded numbers, no banned or causal language;
  - structure: one sentence per finding, in order;
  - headline: no data values;
  - key values: present in each sentence;
  - direction: a rise is never described as a fall;
  - sentence count and length: relative to the template, plus room in the widget
    for the daily check-in;
  - second person: each sentence addresses the reader.

## In CI (every push)

`swift test --package-path Packages/VivraCore` runs the evals tests. They check that:

- the templates pass every scorer on every case;
- each scorer catches a deliberately bad answer;
- every file in `recorded/` still passes.

## Live, on a Mac with Apple Intelligence

From the repository root:

```
swift run --package-path Packages/Narrative vivra-evals
```

Options:

- `--samples N`: runs per case (default 3).
- `--cases hand-`: only cases whose id starts with the given prefix.
- `--output DIR`: where to write the results.
- `--record`: also save the passing model outputs to `recorded/` for CI.

The runner writes `results/evals-<time>.json` and `results/evals-<time>.md`. The
Markdown report shows each model sentence next to its template, for reading through.

It exits with status 1 if a threshold is missed:

- at least 90% of first drafts pass the validator;
- 100% of shown summaries pass every scorer.

The cases are made-up data, so results contain no one's health information.
`results/` is git-ignored. Commit `recorded/` files when you want CI to guard them.
