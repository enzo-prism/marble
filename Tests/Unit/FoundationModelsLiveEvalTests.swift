import XCTest
@testable import marble

/// Live evaluation of the on-device model parser against the eval corpora.
///
/// This talks to Apple's real on-device language model, so it is nondeterministic,
/// slow, and hardware-gated — it must never run in CI. It is opt-in via an
/// environment variable:
///
///     TEST_RUNNER_MARBLE_FM_EVAL=1 make only TEST=MarbleTests/FoundationModelsLiveEvalTests
///
/// Run where the model actually answers: an Apple-Silicon Mac with Apple
/// Intelligence enabled and a simulator runtime matching the host OS (an iOS 26
/// simulator on a macOS 27 host reports `.available` but every call fails for
/// missing model assets). The tests gate on aggregate pass rates rather than
/// per-case exactness, because model output legitimately varies run to run.
@MainActor
final class FoundationModelsLiveEvalTests: MarbleTestCase {

    /// Minimum fraction of all `.all` cases the parse path must satisfy.
    private static let requiredPassRate = 0.8
    /// Prose is gated on its own: notation cases are solved deterministically,
    /// so an overall rate can hide a model path that fails most prose.
    private static let requiredProsePassRate = 0.7
    /// The hard corpus is realistic dictation, shorthand, and known parser
    /// traps; its bar is lower and exists to catch regressions.
    private static let requiredHardPassRate = 0.6

    func testLiveModelPassRateOnCorpus() async throws {
        try skipUnlessLiveModel()
        let results = await evaluate(WorkoutParseEvalCase.all, label: "corpus")
        let prose = results.filter { $0.tier == .prose }
        assertRate(results, atLeast: Self.requiredPassRate, label: "corpus")
        assertRate(prose, atLeast: Self.requiredProsePassRate, label: "corpus prose")
    }

    func testLiveModelPassRateOnHardCorpus() async throws {
        try skipUnlessLiveModel()
        let results = await evaluate(WorkoutParseEvalCase.hard, label: "hard corpus")
        assertRate(results, atLeast: Self.requiredHardPassRate, label: "hard corpus")
    }

    // MARK: - Helpers

    private struct CaseResult {
        var name: String
        var tier: WorkoutParseEvalCase.Tier
        var pass: Bool
        var failures: [String]
        var seconds: Double
    }

    private func skipUnlessLiveModel() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MARBLE_FM_EVAL"] == "1",
            "Live model eval is opt-in: set MARBLE_FM_EVAL=1 to run. Skipped so CI never depends on Apple Intelligence."
        )
        try XCTSkipUnless(
            FoundationModelsWorkoutScanParser.isAvailable,
            "On-device language model is not available on this machine (needs Apple Silicon with Apple Intelligence enabled)."
        )
    }

    private func evaluate(_ cases: [WorkoutParseEvalCase], label: String) async -> [CaseResult] {
        var results: [CaseResult] = []
        for evalCase in cases {
            // Each case carries the user's preferred unit, as the app does.
            let parser = FoundationModelsWorkoutScanParser(defaultWeightUnit: evalCase.defaultWeightUnit)
            let start = Date()
            let draft = await parser.parse(ocrText: evalCase.input, referenceDate: Self.fixedNow)
            let seconds = Date().timeIntervalSince(start)
            let result = WorkoutParseEvalCase.matches(draft, evalCase.expected)
            results.append(CaseResult(
                name: evalCase.name, tier: evalCase.tier, pass: result.pass,
                failures: result.failures, seconds: seconds
            ))
        }

        // Per-case table so a failing run shows exactly where the model fell
        // short, not just an aggregate number.
        print("=== FoundationModels live eval: \(label) (\(results.count) cases) ===")
        for result in results {
            let status = result.pass ? "PASS" : "FAIL"
            print("[\(status)] \(result.name) (\(String(format: "%.1f", result.seconds))s)")
            for failure in result.failures {
                print("        \(failure)")
            }
        }
        let latencies = results.map(\.seconds).sorted()
        if !latencies.isEmpty {
            let mean = latencies.reduce(0, +) / Double(latencies.count)
            let p90 = latencies[min(latencies.count - 1, Int(Double(latencies.count) * 0.9))]
            print("=== Latency: mean \(String(format: "%.1f", mean))s, p90 \(String(format: "%.1f", p90))s ===")
        }
        return results
    }

    private func assertRate(_ results: [CaseResult], atLeast required: Double, label: String) {
        guard !results.isEmpty else { return }
        let passCount = results.filter(\.pass).count
        let passRate = Double(passCount) / Double(results.count)
        let failingNames = results.filter { !$0.pass }.map(\.name)
        print("=== Pass rate (\(label)): \(passCount)/\(results.count) (\(String(format: "%.0f", passRate * 100))%) ===")
        XCTAssertGreaterThanOrEqual(
            passRate,
            required,
            "\(label) pass rate \(String(format: "%.2f", passRate)) is below \(required). Failing cases: \(failingNames.joined(separator: ", "))"
        )
    }
}
