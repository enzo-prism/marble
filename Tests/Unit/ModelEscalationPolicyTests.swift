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
        "Bench 225x5x3",
        "Squat 3x5 at 315 then backoff 2x8 at 275",
        "Squat 100kg 5x5 then 3x10 at 80",
        "bench 3x8 185, incline db 3x10 60s",
        "Front squat 3x5 @ 60 kg, back squat 3x5 @ 100 kg",
        "Ran a mile in 8 minutes then 3 sets of 20 pushups",
        "Did 20 minutes on the bike then 3x10 pushups",
        "Bench 3x8 185 then dropped to 135 for 12",
        "Curls 3x12 with 25s",
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
            XCTAssertTrue(
                ModelEscalationPolicy.shouldRunModel(for: parse(input), sourceText: input, referenceDate: now),
                input
            )
        }
    }

    func testImplausibleInputsNeedModelForKilogramLifters() {
        for input in Self.implausibleInputs {
            XCTAssertTrue(needsModel(input, unit: .kg), input)
        }
    }

    func testReasonsNameTheMisread() {
        XCTAssertTrue(reasons("Bench 225x5x3").contains(.implausibleSetCount))
        XCTAssertTrue(reasons("Squat 100kg 5x5 then 3x10 at 80").contains(.loadLooksLikeSetCount))
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
        let prose = "I did three sets of eight on bench at 185"
        XCTAssertTrue(ModelEscalationPolicy.shouldRunModel(for: parse(prose), sourceText: prose, referenceDate: now))
        XCTAssertTrue(ModelEscalationPolicy.shouldRunModel(for: parse(""), sourceText: "", referenceDate: now))
    }

    func testNameProseDetectionAllowsCompoundLifts() {
        XCTAssertFalse(ModelEscalationPolicy.nameReadsAsProse("Clean and Jerk"))
        XCTAssertFalse(ModelEscalationPolicy.nameReadsAsProse("Incline Dumbbell Press"))
        XCTAssertTrue(ModelEscalationPolicy.nameReadsAsProse("Ran a mile in"))
        XCTAssertTrue(ModelEscalationPolicy.nameReadsAsProse("bench then dropped"))
    }
}
