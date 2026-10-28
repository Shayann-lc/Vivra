import Foundation
import FoundationModels
import Narrative
import NarrativeCore
import NarrativeEvals

// Runs Vivra's eval cases through the on-device model, exactly as the app
// composes summaries, and writes a JSON results file and a Markdown report.
// Run from the repository root on a Mac with Apple Intelligence turned on:
//
//   swift run --package-path Packages/Narrative vivra-evals [options]
//
// Options:
//   --samples N      Runs per case (default 3). The model isn't deterministic.
//   --cases PREFIX   Only cases whose id starts with PREFIX (e.g. "hand-").
//   --output DIR     Where to write results (default evals/results).
//   --record         Also save the passing model outputs to evals/recorded/,
//                    which CI re-scores on every push.
//
// Exit status: 0 when every threshold is met, 1 when one is missed, 2 when
// the model isn't available. The cases are made-up data, so the output holds
// no one's health information.

func say(_ text: String) {
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
}

func fail(_ text: String, status: Int32) -> Never {
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(status)
}

var samples = 3
var prefix: String?
var output = "evals/results"
var record = false
var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    switch argument {
    case "--samples":
        guard let value = arguments.next().flatMap(Int.init), value > 0 else {
            fail("--samples needs a number", status: 2)
        }
        samples = value
    case "--cases":
        guard let value = arguments.next() else { fail("--cases needs a prefix", status: 2) }
        prefix = value
    case "--output":
        guard let value = arguments.next() else { fail("--output needs a directory", status: 2) }
        output = value
    case "--record":
        record = true
    default:
        fail("Unknown option \(argument). See the comment at the top of main.swift.", status: 2)
    }
}

guard FoundationModelsNarrator.isAvailable else {
    fail(
        "The on-device model isn't available (\(SystemLanguageModel.default.availability)). It needs macOS 26 or "
            + "later on Apple silicon, with Apple Intelligence turned on and its model downloaded.",
        status: 2)
}

let cases = EvalCorpus.all.filter { prefix == nil || $0.id.hasPrefix(prefix!) }
guard !cases.isEmpty else { fail("No cases match \(prefix ?? "").", status: 2) }
say("Running \(cases.count) cases × \(samples) samples on the on-device model…")

let outcomes = await EvalRunner.run(cases, narrator: FoundationModelsNarrator(), samples: samples)
let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
    .replacingOccurrences(of: ":", with: "")
let version = ProcessInfo.processInfo.operatingSystemVersionString
let report = EvalRunReport(
    runAt: Date.now.formatted(.iso8601), environment: "macOS \(version), SystemLanguageModel.default",
    samples: samples, outcomes: outcomes)

do {
    let directory = URL(fileURLWithPath: output, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let json = directory.appendingPathComponent("evals-\(stamp).json")
    let markdown = directory.appendingPathComponent("evals-\(stamp).md")
    try report.json().write(to: json)
    try Data(report.markdown(cases: cases).utf8).write(to: markdown)
    say("Wrote \(json.path) and \(markdown.path)")

    if record {
        let recorded = RecordedOutputs(from: report, cases: cases)
        let recordedDirectory = URL(fileURLWithPath: "evals/recorded", isDirectory: true)
        try FileManager.default.createDirectory(at: recordedDirectory, withIntermediateDirectories: true)
        let file = recordedDirectory.appendingPathComponent("recorded-\(stamp).json")
        try recorded.json().write(to: file)
        say("Recorded \(recorded.outputs.count) model outputs in \(file.path)")
    }
} catch {
    fail("Couldn't write the results: \(error.localizedDescription)", status: 2)
}

let summary = report.summary
say("First draft passes the validator: \(Int((summary.firstAttemptValidatorPassRate * 100).rounded()))%")
say("Shown summary passes every scorer: \(Int((summary.shownPassRate * 100).rounded()))%")
say("Fell back to the template: \(Int((summary.fallbackRate * 100).rounded()))%")
if summary.passed {
    say("Passed.")
} else {
    for failure in summary.failures { say("Missed: \(failure)") }
    exit(1)
}
