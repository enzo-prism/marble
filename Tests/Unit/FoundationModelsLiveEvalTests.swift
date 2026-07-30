import XCTest
@testable import marble

/// Live evaluation of the on-device model parser against the full eval corpus.
///
/// This talks to Apple's real on-device language model, so it is nondeterministic,
/// slow, and hardware-gated — it must never run in CI. It is opt-in via an
/// environment variable:
///
///     MARBLE_FM_EVAL=1 make only TEST=MarbleTests/FoundationModelsLiveEvalTests
///
/// Run on an Apple-Silicon Mac with Apple Intelligence enabled (the model must
/// report available). The test prints a per-case table and gates on an aggregate
/// pass rate rather than per-case exactness, because model output legitimately
/// varies run to run — the corpus expectations define the target, the threshold
/// defines "good enough to ship".
@MainActor
final class FoundationModelsLiveEvalTests: MarbleTestCase {

    /// Minimum fraction of corpus cases (both tiers) the model path must satisfy.
    private static let requiredPassRate = 0.8

    func testLiveModelPassRateOnCorpus() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MARBLE_FM_EVAL"] == "1",
            "Live model eval is opt-in: set MARBLE_FM_EVAL=1 to run. Skipped so CI never depends on Apple Intelligence."
        )
        try XCTSkipUnless(
            FoundationModelsWorkoutScanParser.isAvailable,
            "On-device language model is not available on this machine (needs Apple Silicon with Apple Intelligence enabled)."
        )

        let parser = FoundationModelsWorkoutScanParser()
        var results: [(name: String, pass: Bool, failures: [String])] = []

        for evalCase in WorkoutParseEvalCase.all {
            let draft = await parser.parse(ocrText: evalCase.input, referenceDate: Self.fixedNow)
            let result = WorkoutParseEvalCase.matches(draft, evalCase.expected)
            results.append((evalCase.name, result.pass, result.failures))
        }

        // Per-case table so a failing run shows exactly where the model fell short,
        // not just an aggregate number.
        print("=== FoundationModels live eval (\(results.count) cases) ===")
        for result in results {
            let status = result.pass ? "PASS" : "FAIL"
            print("[\(status)] \(result.name)")
            for failure in result.failures {
                print("        \(failure)")
            }
        }

        let passCount = results.filter(\.pass).count
        let passRate = Double(passCount) / Double(results.count)
        let failingNames = results.filter { !$0.pass }.map(\.name)
        print("=== Pass rate: \(passCount)/\(results.count) (\(String(format: "%.0f", passRate * 100))%) ===")

        XCTAssertGreaterThanOrEqual(
            passRate,
            Self.requiredPassRate,
            "Model pass rate \(String(format: "%.2f", passRate)) is below \(Self.requiredPassRate). Failing cases: \(failingNames.joined(separator: ", "))"
        )
    }
}
