import XCTest
import UIKit
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

    private var originalIdleTimerDisabled: Bool?
    override func setUp() {
        super.setUp()
        if ProcessInfo.processInfo.environment["MARBLE_FM_EVAL"] == "1" {
            originalIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }
    override func tearDown() {
        if let originalIdleTimerDisabled { UIApplication.shared.isIdleTimerDisabled = originalIdleTimerDisabled }
        originalIdleTimerDisabled = nil
        super.tearDown()
    }

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

    func testLiveDiagnosticsForIncompleteMovements() async throws {
        try skipUnlessLiveModel()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MARBLE_FM_DIAGNOSTICS"] == "1", "Separate opt-in diagnostic run; not a quality gate")
        let identifiers = ["A1 ", "A3 ", "A4 ", "A6 ", "A8 ", "C3 ", "D3 ", "E3 "]
        _ = await evaluate(WorkoutParseEvalCase.hard.filter { item in identifiers.contains { item.name.hasPrefix($0) } }, label: "diagnostic subset")
    }

    // MARK: - Helpers

    private struct CaseResult {
        var name: String
        var tier: WorkoutParseEvalCase.Tier
        var pass: Bool
        var failures: [String]
        var seconds: Double
        var modelIssue: String?
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
        print("[FM APP STATE] \(UIApplication.shared.applicationState.rawValue)")
        for (index, evalCase) in cases.enumerated() {
            // Independent quality samples should not become a burst-rate-limit
            // stress test of the OS model service. Keep the quality threshold.
            if index > 0 { try? await Task.sleep(for: .seconds(5)) }
            // Each case carries the user's preferred unit, as the app does.
            let parser = FoundationModelsWorkoutScanParser(defaultWeightUnit: evalCase.defaultWeightUnit)
            print("[FM START] \(evalCase.name)")
            let start = Date()
            let draft = await parser.parse(ocrText: evalCase.input, referenceDate: Self.fixedNow)
            let seconds = Date().timeIntervalSince(start)
            let result = WorkoutParseEvalCase.matches(draft, evalCase.expected)
            #if DEBUG
            if !result.pass {
                let raw = parser.lastModelCandidates
                let grounded = raw.map {
                    WorkoutDraftArbiter.choose(deterministic: .init(), model: $0, sourceText: evalCase.input,
                                              defaultWeightUnit: evalCase.defaultWeightUnit)
                }
                if let data = try? JSONEncoder().encode(["raw": raw, "grounded": grounded, "final": [draft]]) {
                    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                    attachment.name = "FoundationModels-Failure-\(evalCase.name.prefix(2)).json"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
            #endif
            results.append(CaseResult(
                name: evalCase.name, tier: evalCase.tier, pass: result.pass,
                failures: result.failures, seconds: seconds,
                modelIssue: parser.lastModelIssue.map { String(describing: $0) }
            ))
            print("[FM END] \(evalCase.name): \(result.pass ? "PASS" : "FAIL"), \(String(format: "%.1f", seconds))s, model issue: \(String(describing: parser.lastModelIssue))")
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
        let report: [String: Any] = [
            "label": label,
            "recordedAt": ISO8601DateFormatter().string(from: Date()),
            "modelAvailable": FoundationModelsWorkoutScanParser.isAvailable,
            "cases": results.map { result in
                ["name": result.name, "tier": String(describing: result.tier),
                 "passed": result.pass, "failures": result.failures,
                 "seconds": result.seconds, "modelIssue": result.modelIssue ?? "none"] as [String: Any]
            }
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "FoundationModels-\(label)-metrics.json"
            attachment.lifetime = .keepAlways
            add(attachment)
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
