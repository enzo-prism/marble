import XCTest
@testable import marble

/// Pins the arbiter's choice between the deterministic notation parse and the
/// on-device model parse: empty-draft fast paths, score-based selection, the
/// deterministic tie-break, cross-draft date/title merging, and the NxM
/// expected-set-count extraction the scoring leans on.
@MainActor
final class WorkoutDraftArbiterTests: MarbleTestCase {

    // MARK: - Draft builders

    private func draft(
        title: String = "Push day",
        performedAt: Date? = nil,
        exercises: [ParsedExerciseDraft]
    ) -> ParsedWorkoutDraft {
        ParsedWorkoutDraft(performedAt: performedAt, title: title, exercises: exercises)
    }

    private func exercise(_ name: String, sets: [ParsedSetDraft]) -> ParsedExerciseDraft {
        ParsedExerciseDraft(name: name, sets: sets)
    }

    private func set(weight: Double? = nil, reps: Int? = nil) -> ParsedSetDraft {
        ParsedSetDraft(weight: weight, reps: reps)
    }

    private func benchSets(count: Int, weight: Double = 185, reps: Int = 8) -> [ParsedSetDraft] {
        (0..<count).map { _ in set(weight: weight, reps: reps) }
    }

    // MARK: - Fast paths

    func testNilModelReturnsDeterministic() {
        let deterministic = draft(exercises: [exercise("Bench", sets: benchSets(count: 3))])
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: nil, sourceText: "Bench 3x8 @ 185"
        )
        XCTAssertEqual(chosen, deterministic)
    }

    func testEmptyModelReturnsDeterministic() {
        let deterministic = draft(exercises: [exercise("Bench", sets: benchSets(count: 3))])
        let emptyModel = draft(exercises: [])
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: emptyModel, sourceText: "Bench 3x8 @ 185"
        )
        XCTAssertEqual(chosen, deterministic)
    }

    func testEmptyDeterministicReturnsModel() {
        let deterministic = draft(exercises: [])
        let model = draft(exercises: [exercise("Bench Press", sets: benchSets(count: 3))])
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: model,
            sourceText: "three sets of eight on bench at 185"
        )
        XCTAssertEqual(chosen.exercises, model.exercises)
    }

    // MARK: - Score-based selection

    func testDeterministicWinsWhenModelCollapsesSets() {
        let text = "Bench 3x8 @ 185"
        let deterministic = draft(exercises: [exercise("Bench", sets: benchSets(count: 3))])
        // The model read the same line but folded 3x8 into a single set.
        let model = draft(exercises: [exercise("Bench Press", sets: benchSets(count: 1))])
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: model, sourceText: text
        )
        XCTAssertEqual(chosen.exercises, deterministic.exercises)
        XCTAssertEqual(chosen.totalSetCount, 3)
    }

    func testModelWinsOnProseEvenWithoutDigitMatchedNumbers() {
        // No digits in the text, so numeric fidelity can't reward the model —
        // but the deterministic parser found nothing, so the model must still win.
        let text = "three sets of eight on bench at one eighty five"
        let deterministic = draft(exercises: [])
        let model = draft(exercises: [exercise("Bench Press", sets: benchSets(count: 3))])
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: model, sourceText: text
        )
        XCTAssertEqual(chosen.exercises, model.exercises)
    }

    func testHallucinatedWeightScoresLowerThanFaithfulDraft() {
        let text = "Bench 3x8 @ 185"
        let faithful = draft(exercises: [exercise("Bench", sets: benchSets(count: 3, weight: 185))])
        let hallucinated = draft(exercises: [exercise("Bench", sets: benchSets(count: 3, weight: 999))])
        XCTAssertLessThan(
            WorkoutDraftArbiter.score(hallucinated, against: text),
            WorkoutDraftArbiter.score(faithful, against: text)
        )
    }

    func testTieGoesToDeterministic() {
        // Structurally identical drafts (identical scores) that differ only in
        // exercise naming — the deterministic one must be returned.
        let text = "Bench 3x8 @ 185"
        let deterministic = draft(exercises: [exercise("Bench", sets: benchSets(count: 3))])
        let model = draft(exercises: [exercise("Barbell Bench Press", sets: benchSets(count: 3))])
        XCTAssertEqual(
            WorkoutDraftArbiter.score(deterministic, against: text),
            WorkoutDraftArbiter.score(model, against: text)
        )
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: model, sourceText: text
        )
        XCTAssertEqual(chosen.exercises[0].name, "Bench")
    }

    // MARK: - Cross-draft merging

    func testWinnerInheritsLosersDate() {
        let text = "Bench 3x8 @ 185"
        let deterministic = draft(exercises: [exercise("Bench", sets: benchSets(count: 3))])
        // Model loses on set count but is the only draft that read the date header.
        let model = draft(
            performedAt: Self.fixedNow,
            exercises: [exercise("Bench", sets: benchSets(count: 1))]
        )
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: model, sourceText: text
        )
        XCTAssertEqual(chosen.exercises, deterministic.exercises)
        XCTAssertEqual(chosen.performedAt, Self.fixedNow)
    }

    func testWinnerInheritsLosersRealTitleOverPlaceholder() {
        let text = "Bench 3x8 @ 185"
        let deterministic = draft(
            title: "Typed workout",
            exercises: [exercise("Bench", sets: benchSets(count: 3))]
        )
        let model = draft(
            title: "Push Day A",
            exercises: [exercise("Bench", sets: benchSets(count: 1))]
        )
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: model, sourceText: text
        )
        XCTAssertEqual(chosen.exercises, deterministic.exercises)
        XCTAssertEqual(chosen.title, "Push Day A")
    }

    func testRealTitleIsNotReplacedByLosersTitle() {
        let text = "Bench 3x8 @ 185"
        let deterministic = draft(
            title: "Upper body",
            exercises: [exercise("Bench", sets: benchSets(count: 3))]
        )
        let model = draft(
            title: "Push Day A",
            exercises: [exercise("Bench", sets: benchSets(count: 1))]
        )
        let chosen = WorkoutDraftArbiter.choose(
            deterministic: deterministic, model: model, sourceText: text
        )
        XCTAssertEqual(chosen.title, "Upper body")
    }

    // MARK: - expectedSetCount

    func testExpectedSetCountSumsSetsByRepsTokens() {
        XCTAssertEqual(WorkoutDraftArbiter.expectedSetCount(in: "Bench 3x8 Squat 5x5"), 8)
    }

    func testExpectedSetCountIgnoresWeightByRepsTokens() {
        // 315 is a load, not a set count — above the disambiguation threshold.
        XCTAssertNil(WorkoutDraftArbiter.expectedSetCount(in: "Deadlift 315x5"))
    }

    func testExpectedSetCountNilWithoutNumbers() {
        XCTAssertNil(WorkoutDraftArbiter.expectedSetCount(in: "no numbers here"))
    }

    func testExpectedSetCountHandlesSpacedX() {
        XCTAssertEqual(WorkoutDraftArbiter.expectedSetCount(in: "Plank 3 x 60s"), 3)
    }

    func testExpectedSetCountHandlesUnicodeMultiplicationSign() {
        XCTAssertEqual(WorkoutDraftArbiter.expectedSetCount(in: "Bench 3×8"), 3)
    }
}
