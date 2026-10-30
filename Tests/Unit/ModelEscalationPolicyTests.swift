import XCTest
@testable import marble

/// Pins when a deterministic parse is trusted without the on-device model. The
/// implausible inputs are real pastes the notation parser used to claim with no
/// dropped lines — so the model was skipped exactly when it was needed — and
/// the clean side is the eval corpus's notation tier, which must never pay a
/// model pass. Every case runs the real `HandwrittenWorkoutParser`.
@MainActor
final class ModelEscalationPolicyTests: MarbleTestCase {

    private func parse(_ text: String, unit: WeightUnit = .lb) -> WorkoutParseResult {
        HandwrittenWorkoutParser.parseDetailed(text, referenceDate: now, defaultWeightUnit: unit)
    }

    private func needsModel(_ text: String, unit: WeightUnit = .lb) -> Bool {
        ModelEscalationPolicy.deterministicDraftNeedsModel(parse(text, unit: unit).draft, sourceText: text)
    }

    private func reasons(_ text: String, unit: WeightUnit = .lb) -> [ModelEscalationPolicy.Reason] {
        ModelEscalationPolicy.reasons(for: parse(text, unit: unit).draft, sourceText: text)
    }

    // MARK: - Implausible drafts escalate

    static let implausibleInputs = [
        "Squat 3x5 at 315 then backoff 2x8 at 275",
        "bench 3x8 185, incline db 3x10 60s",
        "Front squat 3x5 @ 60 kg, back squat 3x5 @ 100 kg",
        "Ran a mile in 8 minutes then 3 sets of 20 pushups",
        "Did 20 minutes on the bike then 3x10 pushups",
        "Curls 3x12 with 25s",
        "Pushups 24x10",
    ]

    /// Misreads the parser used to claim and now leaves unresolved instead
    /// (an impossible set count, two prescriptions on one line). A dropped
    /// line escalates on its own, so these must reach the model too.
    static let unresolvedInputs = [
        "Bench 225x5x3",
        "Squat 100kg 5x5 then 3x10 at 80",
        "Bench 3x8 185 then dropped to 135 for 12",
    ]

    func testImplausibleInputsParseWithoutDroppedLines() {
        // The premise: a dropped-lines gate alone would skip the model here.
        for input in Self.implausibleInputs {
            let result = parse(input)
            XCTAssertTrue(result.droppedLines.isEmpty, input)
            XCTAssertTrue(result.draft.hasContent, input)
        }
    }

    func testImplausibleInputsNeedModel() {
        for input in Self.implausibleInputs {
            XCTAssertTrue(needsModel(input), input)
        }
        for input in Self.implausibleInputs + Self.unresolvedInputs {
            XCTAssertTrue(
                ModelEscalationPolicy.shouldRunModel(for: parse(input), sourceText: input, referenceDate: now),
                input
            )
        }
    }

    func testUnresolvedInputsAreDroppedRatherThanMisread() {
        for input in Self.unresolvedInputs {
            let result = parse(input)
            XCTAssertEqual(result.droppedLines, [input], input)
            XCTAssertFalse(result.draft.hasContent, input)
        }
    }

    func testImplausibleInputsNeedModelForKilogramLifters() {
        for input in Self.implausibleInputs {
            XCTAssertTrue(needsModel(input, unit: .kg), input)
        }
    }

    func testReasonsNameTheMisread() {
        XCTAssertTrue(reasons("Pushups 24x10").contains(.implausibleSetCount))
        XCTAssertTrue(reasons("bench 3x8 185, incline db 3x10 60s").contains(.loadLooksLikeSetCount))
        XCTAssertTrue(reasons("Ran a mile in 8 minutes then 3 sets of 20 pushups").contains(.proseInName))
        XCTAssertTrue(reasons("Front squat 3x5 @ 60 kg, back squat 3x5 @ 100 kg").contains(.multipleMovementsOnLine))
        XCTAssertEqual(reasons("Curls 3x12 with 25s"), [.ignoredLoad])
    }

    // MARK: - Clean notation stays deterministic

    func testCorpusNotationCasesDoNotNeedModel() {
        let cases = WorkoutParseEvalCase.notationCases
        XCTAssertGreaterThanOrEqual(cases.count, 20)
        for testCase in cases {
            let result = parse(testCase.input, unit: testCase.defaultWeightUnit)
            XCTAssertEqual(
                ModelEscalationPolicy.reasons(for: result.draft, sourceText: testCase.input), [],
                testCase.name
            )
            XCTAssertFalse(
                ModelEscalationPolicy.shouldRunModel(for: result, sourceText: testCase.input, referenceDate: now),
                testCase.name
            )
        }
    }

    func testEverydayNotationDoesNotNeedModel() {
        let lines = [
            "Curls 3x12 @ 20 rest 90s",
            "Dumbbell curl 3x12 @ 20, rest 90s",
            "Lateral raise 3x15 @ 15",
            "Clean and Jerk 5x2 @ 60 kg",
            "Pushups 3x20 rest 60s",
            "EMOM 30 min: 5 burpees",
            "Bench 3x8 @ 185 RPE 8",
            "Pull-ups 3x8 @ 20 kg",
            "Farmer carry 3x40m @ 32kg",
            "Row 2000m 7:30",
            "Chin-ups 4x6 bodyweight",
            "Plank 3 x 45s",
            "Bench 3x8 @ 185 tempo 20x1",
            "Bulgarian split squat 3x10 @ 20 each leg",
            "Squat 3x5 @ 102.5",
        ]
        for unit in [WeightUnit.lb, .kg] {
            for line in lines {
                XCTAssertEqual(reasons(line, unit: unit), [], "\(line) (\(unit))")
            }
        }
    }

    // MARK: - The shared gate

    func testGateRunsModelForDroppedLinesAndEmptyDrafts() {
        let prose = "Bench three sets of 8 at 185, shoulders felt tight"
        XCTAssertFalse(parse(prose).droppedLines.isEmpty)
        XCTAssertTrue(ModelEscalationPolicy.shouldRunModel(for: parse(prose), sourceText: prose, referenceDate: now))
        XCTAssertTrue(ModelEscalationPolicy.shouldRunModel(for: parse(""), sourceText: "", referenceDate: now))
    }

    func testNameProseDetectionAllowsCompoundLifts() {
        XCTAssertFalse(ModelEscalationPolicy.nameReadsAsProse("Clean and Jerk"))
        XCTAssertFalse(ModelEscalationPolicy.nameReadsAsProse("Incline Dumbbell Press"))
        XCTAssertTrue(ModelEscalationPolicy.nameReadsAsProse("Ran a mile in"))
        XCTAssertTrue(ModelEscalationPolicy.nameReadsAsProse("bench then dropped"))
    }
    func testExplicitNumericCountsEscalateWhenNotRepresented() {
        let input = "jump rope 5 rounds of 3 min, 1 min rest"
        XCTAssertTrue(reasons(input).contains(.explicitSetCountMismatch), input)
        XCTAssertTrue(ModelEscalationPolicy.shouldRunModel(for: parse(input), sourceText: input, referenceDate: now))
    }

    func testProseTheParserReadsCorrectlySkipsTheModel() {
        // Once the notation parser represents every stated count and load,
        // there is nothing for the model to fix.
        for (input, sets, reps, weight) in [
            ("tricep extentions 3 sets 12 reps 40lbs", 3, 12, 40.0),
            ("I did three sets of eight on bench at 185", 3, 8, 185.0),
        ] {
            let result = parse(input)
            let exercise = result.draft.exercises.first
            XCTAssertEqual(exercise?.sets.count, sets, input)
            XCTAssertEqual(exercise?.sets.first?.reps, reps, input)
            XCTAssertEqual(exercise?.sets.first?.weight, weight, input)
            XCTAssertFalse(ModelEscalationPolicy.shouldRunModel(for: result, sourceText: input, referenceDate: now), input)
        }
    }

    func testExplicitPluralLoadEscalatesForDistanceWork() {
        let input = "farmer carry 3x40m with 32s"
        XCTAssertTrue(reasons(input, unit: .kg).contains(.ignoredLoad))
        XCTAssertFalse(reasons("Farmer carry 3x40m @ 32kg", unit: .kg).contains(.ignoredLoad))
        for input in ["Plank 3x45s with 30s rest", "Plank 3x45s with 30s of rest",
                      "Plank 3x45s with 30s between sets", "Plank 3x45s with 30s, rest"] {
            XCTAssertFalse(reasons(input).contains(.ignoredLoad), input)
        }
    }

    func testCountEvidenceIsNotAppliedAcrossMultipleMovements() {
        let input = "Bench 3 sets of 8 and Squat 5 sets of 5"
        XCTAssertFalse(reasons(input).contains(.explicitSetCountMismatch))
        XCTAssertFalse(reasons("Bench 3x8 3 sets").contains(.explicitSetCountMismatch))
    }

}
