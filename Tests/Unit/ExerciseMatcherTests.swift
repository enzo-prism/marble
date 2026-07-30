import XCTest
@testable import marble

/// Pins the behavior of the pure exercise-name matcher used by the free-text
/// import flow. The matcher works over a snapshot of names, so these tests need
/// no model context.
@MainActor
final class ExerciseMatcherTests: MarbleTestCase {

    private func matcher(_ names: [String]) -> ExerciseMatcher {
        ExerciseMatcher(candidates: names.map { ExerciseMatcher.Candidate(id: UUID(), name: $0) })
    }

    // MARK: - Exact and normalized matches

    func testExactNameMatchesWithExactConfidence() {
        let match = matcher(["Bench Press", "Squat"]).bestMatch(for: "Bench Press")
        XCTAssertEqual(match?.candidate.name, "Bench Press")
        XCTAssertEqual(match?.confidence, .exact)
    }

    func testCaseAndPunctuationAreIgnored() {
        let match = matcher(["Chin-Up"]).bestMatch(for: "chin up")
        XCTAssertEqual(match?.candidate.name, "Chin-Up")
        XCTAssertEqual(match?.confidence, .exact)
    }

    func testPluralFoldsToSingular() {
        let match = matcher(["Hammer Curl"]).bestMatch(for: "hammer curls")
        XCTAssertEqual(match?.candidate.name, "Hammer Curl")
        XCTAssertEqual(match?.confidence, .exact)
    }

    // MARK: - Aliases

    func testGymShorthandExpands() {
        let m = matcher(["Incline Dumbbell Press", "Overhead Press", "Romanian Deadlift"])
        XCTAssertEqual(m.bestMatch(for: "incline db press")?.candidate.name, "Incline Dumbbell Press")
        XCTAssertEqual(m.bestMatch(for: "incline db press")?.confidence, .exact)
        XCTAssertEqual(m.bestMatch(for: "OHP")?.candidate.name, "Overhead Press")
        XCTAssertEqual(m.bestMatch(for: "OHP")?.confidence, .exact)
        XCTAssertEqual(m.bestMatch(for: "RDLs")?.candidate.name, "Romanian Deadlift")
    }

    // MARK: - Typos and word order

    func testTyposStillMatchStrongly() {
        let match = matcher(["Bench Press"]).bestMatch(for: "bnech press")
        XCTAssertEqual(match?.candidate.name, "Bench Press")
        if let match {
            XCTAssertGreaterThanOrEqual(match.confidence, .strong)
        }
    }

    func testWordOrderDoesNotMatter() {
        let match = matcher(["Incline Dumbbell Press"]).bestMatch(for: "dumbbell incline press")
        XCTAssertEqual(match?.candidate.name, "Incline Dumbbell Press")
    }

    // MARK: - Partial matches

    func testSubsetNameIsOnlyLikely() {
        let match = matcher(["Bench Press"]).bestMatch(for: "Bench")
        XCTAssertEqual(match?.candidate.name, "Bench Press")
        XCTAssertEqual(match?.confidence, .likely)
    }

    func testUnrelatedNamesDoNotMatch() {
        let m = matcher(["Bench Press", "Squat", "Deadlift"])
        XCTAssertNil(m.bestMatch(for: "Face Pull"))
        XCTAssertNil(m.bestMatch(for: "Run"))
    }

    func testShortTokensRequireEquality() {
        XCTAssertNil(matcher(["Row"]).bestMatch(for: "Run"))
    }

    // MARK: - Ranking

    func testTopMatchesRanksClosestFirst() {
        let matches = matcher(["Bench Press", "Incline Bench Press", "Leg Press"]).topMatches(for: "bench press")
        XCTAssertEqual(matches.first?.candidate.name, "Bench Press")
        XCTAssertTrue(matches.contains { $0.candidate.name == "Incline Bench Press" })
        XCTAssertFalse(matches.contains { $0.candidate.name == "Leg Press" })
    }

    func testEmptyInputsAreSafe() {
        XCTAssertNil(matcher([]).bestMatch(for: "Bench"))
        XCTAssertNil(matcher(["Bench"]).bestMatch(for: "   "))
        XCTAssertTrue(matcher(["Bench"]).topMatches(for: "").isEmpty)
    }
}
