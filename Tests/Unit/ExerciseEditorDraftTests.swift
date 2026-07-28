import XCTest
@testable import marble

@MainActor
final class ExerciseEditorDraftTests: MarbleTestCase {
    func testNewDraftStartsWithAValidStrengthSetup() {
        let draft = ExerciseEditorDraft.new(initialName: "  Incline Press  ")

        XCTAssertEqual(draft.name, "Incline Press")
        XCTAssertEqual(draft.kind, .strength)
        XCTAssertEqual(draft.metrics, .weightAndRepsRequired)
        XCTAssertEqual(draft.resistanceTrackingStyle, .totalLoad)
        XCTAssertTrue(draft.validationErrors(existingExercises: [], excluding: nil).isEmpty)
    }

    func testKindInferenceDistinguishesSprintFromRun() {
        XCTAssertEqual(
            ExerciseKind.infer(
                metrics: .distanceAndDurationRequired,
                resistanceStyle: .totalLoad,
                category: .run,
                hasSprintPrescription: true
            ),
            .sprint
        )
        XCTAssertEqual(
            ExerciseKind.infer(
                metrics: .distanceAndDurationRequired,
                resistanceStyle: .totalLoad,
                category: .run,
                hasSprintPrescription: false
            ),
            .run
        )
        XCTAssertEqual(
            ExerciseKind.infer(
                name: "Sprint",
                metrics: .distanceAndDurationRequired,
                resistanceStyle: .totalLoad,
                category: .power,
                hasSprintPrescription: false
            ),
            .sprint
        )
    }

    func testApplyingSprintAndRunUsesSafeDefaults() {
        var draft = ExerciseEditorDraft.new(initialName: "Track Work")

        draft.apply(.sprint)
        XCTAssertEqual(draft.kind, .sprint)
        XCTAssertEqual(draft.category, .run)
        XCTAssertEqual(draft.metrics, .distanceAndDurationRequired)
        XCTAssertEqual(draft.preferredDistanceUnit, .meters)
        XCTAssertTrue(draft.usesSprintPrescription)

        draft.apply(.run)
        XCTAssertEqual(draft.kind, .run)
        XCTAssertEqual(draft.preferredDistanceUnit, .kilometers)
        XCTAssertFalse(draft.usesSprintPrescription)
        XCTAssertTrue(draft.sprintErrors.isEmpty)

        draft.apply(.strength)
        XCTAssertEqual(draft.category, .other)
    }

    func testDuplicateNameValidationIsTrimmedAndCaseInsensitive() {
        let existing = Exercise(
            name: "Bench Press",
            category: .chest,
            metrics: .weightAndRepsRequired,
            defaultRestSeconds: 120
        )
        var draft = ExerciseEditorDraft.new(initialName: " bench press ")

        XCTAssertEqual(
            draft.nameError(existingExercises: [existing], excluding: nil),
            "\"Bench Press\" already exists."
        )

        draft.name = "Incline Press"
        XCTAssertNil(draft.nameError(existingExercises: [existing], excluding: nil))
    }

    func testSprintRangeValidationRejectsReversedBounds() {
        var draft = ExerciseEditorDraft.new(initialName: "150m Sprint")
        draft.apply(.sprint)
        draft.sprintVariants[0].distance = 150
        draft.sprintVariants[0].repetitionCount = 4
        draft.sprintVariants[0].targetMode = .range
        draft.sprintVariants[0].targetLowerSeconds = 21
        draft.sprintVariants[0].targetUpperSeconds = 19

        XCTAssertTrue(draft.sprintErrors.contains(
            "The slow end must be equal to or slower than the fast end."
        ))

        draft.sprintVariants[0].targetLowerSeconds = 19
        draft.sprintVariants[0].targetUpperSeconds = 21
        XCTAssertTrue(draft.sprintErrors.isEmpty)
    }

    func testSprintVariantDraftResolvesDecimalSecondsToTenths() {
        var variant = SprintVariantDraft.new()
        variant.targetMode = .time
        variant.targetSeconds = 14.5
        XCTAssertEqual(variant.resolvedTarget, SprintTargetTenths(lowerTenths: 145, upperTenths: 145))

        variant.targetMode = .range
        variant.targetLowerSeconds = 19
        variant.targetUpperSeconds = 21.5
        XCTAssertEqual(variant.resolvedTarget, SprintTargetTenths(lowerTenths: 190, upperTenths: 215))
    }

    func testChangingTrackingFieldsFlagsHistoricalInterpretation() {
        let exercise = Exercise(
            name: "Bench Press",
            category: .chest,
            metrics: .weightAndRepsRequired,
            defaultRestSeconds: 120
        )
        var draft = ExerciseEditorDraft(exercise: exercise, prescription: nil)

        XCTAssertFalse(draft.changesHistoricalInterpretation(from: exercise))

        draft.apply(.dualDumbbell)
        XCTAssertTrue(draft.changesHistoricalInterpretation(from: exercise))
    }

    func testSprintPlanChangesFlagPlannedWorkoutImpact() {
        let exercise = Exercise(
            name: "150m Sprint",
            category: .run,
            preferredDistanceUnit: .meters,
            metrics: .distanceAndDurationRequired,
            defaultRestSeconds: 180
        )
        let prescription = SprintPrescription(
            exerciseID: exercise.id,
            distance: 150,
            repetitionCount: 4,
            targetLowerSeconds: 19,
            targetUpperSeconds: 21
        )
        let original = ExerciseEditorDraft(exercise: exercise, prescription: prescription)
        var changed = original

        changed.sprintVariants[0].targetUpperSeconds = 22

        XCTAssertTrue(changed.changesPlannedWorkoutBehavior(from: original))
        XCTAssertFalse(original.changesPlannedWorkoutBehavior(from: original))
    }
}
