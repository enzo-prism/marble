import XCTest
@testable import marble

/// Runs the shared parsing eval corpus against the deterministic parser.
///
/// Two invariants are pinned here:
///   1. Every `.notation` case parses exactly — these are the documented shorthand
///      patterns and any regression is a bug.
///   2. Every `.prose` case does NOT parse exactly — that gap is the reason the
///      on-device model path exists. If the deterministic parser ever learns a
///      prose case, this test flags it so the case can be re-tiered to `.notation`
///      instead of silently overlapping.
@MainActor
final class WorkoutParseCorpusTests: MarbleTestCase {

    func testNotationCasesParseExactly() {
        for evalCase in WorkoutParseEvalCase.all where evalCase.tier == .notation {
            XCTContext.runActivity(named: evalCase.name) { _ in
                let draft = HandwrittenWorkoutParser.parse(evalCase.input, referenceDate: Self.fixedNow)
                let result = WorkoutParseEvalCase.matches(draft, evalCase.expected)
                if !result.pass {
                    XCTFail("""
                    Notation case "\(evalCase.name)" failed the deterministic parser.
                    Input: \(evalCase.input)
                    \(result.failures.joined(separator: "\n"))
                    """)
                }
            }
        }
    }

    func testProseCasesRequireTheModel() {
        for evalCase in WorkoutParseEvalCase.all where evalCase.tier == .prose {
            XCTContext.runActivity(named: evalCase.name) { _ in
                let draft = HandwrittenWorkoutParser.parse(evalCase.input, referenceDate: Self.fixedNow)
                let result = WorkoutParseEvalCase.matches(draft, evalCase.expected)
                if result.pass {
                    XCTFail("""
                    Prose case "\(evalCase.name)" now parses exactly with the deterministic \
                    parser. Re-tier it to .notation so the corpus keeps documenting the \
                    boundary between the two parsers.
                    Input: \(evalCase.input)
                    """)
                }
            }
        }
    }
}
