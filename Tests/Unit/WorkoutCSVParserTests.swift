import XCTest
@testable import marble

@MainActor
final class WorkoutCSVParserTests: MarbleTestCase {
    func testHevyExportSplitsWorkoutsByTitleAndStart() {
        let csv = """
        title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_lbs,reps,distance_miles,duration_seconds,rpe
        Push Day,"28 Mar 2025, 17:29","28 Mar 2025, 18:45",,Bench Press,,,0,normal,185,8,0,0,
        Push Day,"28 Mar 2025, 17:29","28 Mar 2025, 18:45",,Bench Press,,,1,normal,185,8,0,0,
        Push Day,"28 Mar 2025, 17:29","28 Mar 2025, 18:45",,OHP,,,0,normal,95,8,0,0,
        Pull Day,"29 Mar 2025, 17:00","29 Mar 2025, 18:00",,Row,,,0,normal,135,10,0,0,
        """
        let result = try! XCTUnwrap(WorkoutCSVParser.parse(csv))
        XCTAssertEqual(result.kind, .hevyCSV)
        XCTAssertEqual(result.workouts.count, 2)
        XCTAssertEqual(result.workouts[0].draft.title, "Push Day")
        XCTAssertEqual(result.workouts[0].draft.exercises.map(\.name), ["Bench Press", "OHP"])
        XCTAssertEqual(result.workouts[0].draft.exercises[0].sets.count, 2)
        XCTAssertEqual(result.workouts[0].draft.exercises[0].sets[0].weight, 185)
        XCTAssertEqual(result.workouts[0].draft.exercises[0].sets[0].weightUnit, .lb)
        XCTAssertEqual(result.workouts[0].draft.exercises[0].sets[0].reps, 8)
        XCTAssertEqual(result.workouts[1].draft.title, "Pull Day")
        XCTAssertEqual(result.workouts[1].draft.exercises[0].name, "Row")
        XCTAssertTrue(result.workouts[0].identityKey.contains("hevyCSV"))
        XCTAssertNotEqual(result.workouts[0].identityKey, result.workouts[1].identityKey)
        XCTAssertEqual(result.workouts[0].draft.durationSeconds, 76 * 60)
        XCTAssertNotNil(result.workouts[0].draft.endedAt)
    }

    func testHevyWarmupSetsAreSkipped() {
        let csv = """
        title,start_time,exercise_title,set_index,set_type,weight_lbs,reps
        Push Day,2025-03-28 17:00:00,Bench Press,0,warmup,135,8
        Push Day,2025-03-28 17:00:00,Bench Press,1,normal,185,8
        Push Day,2025-03-28 17:00:00,Bench Press,2,dropset,155,6
        """
        let result = try! XCTUnwrap(WorkoutCSVParser.parse(csv))
        let sets = result.workouts[0].draft.exercises[0].sets
        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets[0].weight, 185)
        XCTAssertEqual(sets[1].weight, 155)
        XCTAssertEqual(sets[1].notes, "Drop set")
    }

    func testWarmupOnlyExportIsNotAWorkout() {
        let csv = """
        title,start_time,exercise_title,set_index,set_type,weight_lbs,reps
        Push Day,2025-03-28 17:00:00,Bench Press,0,warmup,135,8
        """
        XCTAssertNil(WorkoutCSVParser.parse(csv))
    }

    func testHevyRPENotesAndDescriptionRoundTrip() {
        let csv = """
        title,start_time,end_time,description,exercise_title,exercise_notes,set_index,set_type,weight_lbs,reps,rpe
        Push Day,"28 Mar 2025, 17:29","28 Mar 2025, 18:45",Felt strong,Bench Press,paused,0,normal,185,8,8.5
        """
        let result = try! XCTUnwrap(WorkoutCSVParser.parse(csv))
        let draft = result.workouts[0].draft
        XCTAssertEqual(draft.notes, "Felt strong")
        XCTAssertEqual(draft.durationSeconds, 76 * 60)
        let set = draft.exercises[0].sets[0]
        XCTAssertEqual(set.difficulty, 9)
        XCTAssertEqual(set.notes, "paused")
    }

    func testHevyKilogramColumn() {
        let csv = """
        title,start_time,exercise_title,set_index,weight_kg,reps
        Squat Day,2025-03-28 17:00:00,Squat,0,100,5
        """
        let result = try! XCTUnwrap(WorkoutCSVParser.parse(csv))
        let set = result.workouts[0].draft.exercises[0].sets[0]
        XCTAssertEqual(set.weight, 100)
        XCTAssertEqual(set.weightUnit, .kg)
    }

    func testStrongExport() {
        let csv = """
        Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
        2025-01-15 18:00:00,Leg Day,60m,Squat,1,225,5,0,0,,,
        2025-01-15 18:00:00,Leg Day,60m,Squat,2,225,5,0,0,,,
        2025-01-16 18:00:00,Upper,45m,Bench Press,1,185,8,0,0,,,
        """
        let result = try! XCTUnwrap(WorkoutCSVParser.parse(csv))
        XCTAssertEqual(result.kind, .strongCSV)
        XCTAssertEqual(result.workouts.count, 2)
        XCTAssertEqual(result.workouts[0].draft.title, "Leg Day")
        XCTAssertEqual(result.workouts[0].draft.exercises[0].sets.count, 2)
        XCTAssertEqual(result.workouts[0].draft.durationSeconds, 3600)
        XCTAssertEqual(result.workouts[1].draft.exercises[0].name, "Bench Press")
        XCTAssertEqual(result.workouts[1].draft.durationSeconds, 45 * 60)
    }

    func testStrongNotesAndRPE() {
        let csv = """
        Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
        2025-01-15 18:00:00,Leg Day,1h 5m,Squat,1,225,5,0,0,belt,Heavy day,7
        """
        let result = try! XCTUnwrap(WorkoutCSVParser.parse(csv))
        let draft = result.workouts[0].draft
        XCTAssertEqual(draft.durationSeconds, 65 * 60)
        XCTAssertEqual(draft.notes, "Heavy day")
        XCTAssertEqual(draft.exercises[0].sets[0].notes, "belt")
        XCTAssertEqual(draft.exercises[0].sets[0].difficulty, 7)
    }

    func testWorkoutDurationTokens() {
        XCTAssertEqual(CSVNumber.workoutDurationToken("60m"), 3600)
        XCTAssertEqual(CSVNumber.workoutDurationToken("1h 5m"), 3900)
        XCTAssertEqual(CSVNumber.workoutDurationToken("1:16:00"), 76 * 60)
        XCTAssertEqual(CSVNumber.workoutDurationToken("45"), 45 * 60)
        XCTAssertNil(CSVNumber.workoutDurationToken(""))
    }

    func testQuotedCommasInTitle() {
        let csv = """
        title,start_time,exercise_title,set_index,weight_lbs,reps
        "Thursday, Upper","28 Mar 2025, 17:29",Band Pullaparts,0,,20
        """
        let result = try! XCTUnwrap(WorkoutCSVParser.parse(csv))
        XCTAssertEqual(result.workouts[0].draft.title, "Thursday, Upper")
        XCTAssertEqual(result.workouts[0].draft.exercises[0].sets[0].reps, 20)
        XCTAssertNil(result.workouts[0].draft.exercises[0].sets[0].weight)
    }

    func testQuotedNewlinesInNotesStayOneRow() {
        let csv = """
        title,start_time,exercise_title,set_index,weight_lbs,reps,exercise_notes
        Push Day,2025-03-28 17:00:00,Bench Press,0,185,8,"felt strong
        next week go heavier"
        Pull Day,2025-03-29 17:00:00,Row,0,135,10,
        """
        let result = try! XCTUnwrap(WorkoutCSVParser.parse(csv))
        XCTAssertEqual(result.workouts.count, 2)
        XCTAssertEqual(result.workouts[0].draft.exercises[0].name, "Bench Press")
        XCTAssertEqual(result.workouts[1].draft.title, "Pull Day")
        XCTAssertTrue(result.workouts[0].draft.exercises[0].sets[0].notes?.contains("felt strong") == true)
        XCTAssertTrue(result.workouts[0].draft.exercises[0].sets[0].notes?.contains("next week go heavier") == true)
    }

    func testMergingTwoExportsDropsTheSecondHeader() {
        let first = """
        title,start_time,exercise_title,set_index,weight_lbs,reps
        Push Day,2025-01-15 18:00:00,Bench Press,0,185,8
        """
        let second = """
        title,start_time,exercise_title,set_index,weight_lbs,reps
        Pull Day,2025-01-16 18:00:00,Row,0,135,10
        """
        let merged = WorkoutCSVParser.merging([first, second])
        let result = try! XCTUnwrap(WorkoutCSVParser.parse(merged))
        XCTAssertEqual(result.workouts.count, 2)
        XCTAssertEqual(result.workouts.map(\.draft.title), ["Push Day", "Pull Day"])
    }

    func testNotesTextIsNotTreatedAsCSV() {
        XCTAssertNil(WorkoutCSVParser.parse("Bench 3x8 @ 185, rest 90s\nSquat 5x5"))
        XCTAssertNil(WorkoutCSVParser.parse("name,weight,reps\nnot,a,workout"))
    }

    func testZeroLoadsAreDroppedFromTheSet() {
        let csv = """
        title,start_time,exercise_title,set_index,weight_lbs,reps,duration_seconds
        Cardio,2025-01-15 08:00:00,Run,0,0,0,1500
        """
        let result = try! XCTUnwrap(WorkoutCSVParser.parse(csv))
        let set = result.workouts[0].draft.exercises[0].sets[0]
        XCTAssertNil(set.weight)
        XCTAssertNil(set.reps)
        XCTAssertEqual(set.durationSeconds, 1500)
    }

    func testHevySetIndexResetKeepsTwoBlocksOfTheSameLift() {
        let csv = """
        title,start_time,exercise_title,set_index,set_type,weight_lbs,reps
        Push,2025-03-28 17:00:00,Bulgarian Split Squat,0,normal,95,8
        Push,2025-03-28 17:00:00,Bulgarian Split Squat,1,normal,95,8
        Push,2025-03-28 17:00:00,Bulgarian Split Squat,2,normal,95,8
        Push,2025-03-28 17:00:00,Bulgarian Split Squat,0,normal,75,8
        Push,2025-03-28 17:00:00,Bulgarian Split Squat,1,normal,75,8
        Push,2025-03-28 17:00:00,Bulgarian Split Squat,2,normal,75,8
        """
        let result = try! XCTUnwrap(WorkoutCSVParser.parse(csv))
        let exercises = result.workouts[0].draft.exercises
        XCTAssertEqual(exercises.count, 2)
        XCTAssertEqual(exercises.map(\.name), ["Bulgarian Split Squat", "Bulgarian Split Squat"])
        XCTAssertEqual(exercises[0].sets.map(\.weight), [95, 95, 95])
        XCTAssertEqual(exercises[1].sets.map(\.weight), [75, 75, 75])
    }

    func testHevySupersetIdLandsInSetNotes() {
        let csv = """
        title,start_time,exercise_title,superset_id,set_index,set_type,weight_lbs,reps
        Push,2025-03-28 17:00:00,Bench Press,0,0,normal,185,8
        Push,2025-03-28 17:00:00,Row,0,0,normal,135,10
        """
        let result = try! XCTUnwrap(WorkoutCSVParser.parse(csv))
        let draft = result.workouts[0].draft
        XCTAssertEqual(draft.exercises[0].sets[0].notes, "Superset 0")
        XCTAssertEqual(draft.exercises[1].sets[0].notes, "Superset 0")
    }

    func testStrongBareDistanceUsesPreferredUnit() {
        let csv = """
        Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
        2025-01-15 08:00:00,Cardio,45m,Running,1,0,0,5.0,1800,,,
        """
        let miles = try! XCTUnwrap(WorkoutCSVParser.parse(csv, defaultWeightUnit: .lb))
        XCTAssertEqual(miles.workouts[0].draft.exercises[0].sets[0].distance, 5)
        XCTAssertEqual(miles.workouts[0].draft.exercises[0].sets[0].distanceUnit, .miles)

        let km = try! XCTUnwrap(WorkoutCSVParser.parse(csv, defaultWeightUnit: .kg))
        XCTAssertEqual(km.workouts[0].draft.exercises[0].sets[0].distanceUnit, .kilometers)
    }

    func testSemicolonDelimitedStrongExportWithKilogramHeader() {
        let csv = """
        Date;Workout Name;Duration;Exercise Name;Set Order;Weight (kg);Reps;Distance;Seconds;Notes;Workout Notes;RPE
        2025-01-15 18:00:00;Leg Day;60m;Squat (Barbell);1;100,5;5;0;0;;;8,5
        """
        let result = try! XCTUnwrap(WorkoutCSVParser.parse(csv, defaultWeightUnit: .kg))
        XCTAssertEqual(result.kind, .strongCSV)
        let set = result.workouts[0].draft.exercises[0].sets[0]
        XCTAssertEqual(set.weight, 100.5)
        XCTAssertEqual(set.weightUnit, .kg)
        XCTAssertEqual(set.reps, 5)
        XCTAssertEqual(set.difficulty, 9)
        XCTAssertEqual(result.workouts[0].draft.exercises[0].name, "Squat")
        XCTAssertEqual(result.workouts[0].draft.durationSeconds, 3600)
    }

    func testWeightKilogramParenthesesHeader() {
        let csv = """
        Date,Workout Name,Duration,Exercise Name,Set Order,Weight (kg),Reps,Distance,Seconds,Notes,Workout Notes,RPE
        2025-01-15 18:00:00,Leg Day,60m,Squat (Barbell),1,100,5,0,0,,,
        """
        let result = try! XCTUnwrap(WorkoutCSVParser.parse(csv, defaultWeightUnit: .lb))
        let set = result.workouts[0].draft.exercises[0].sets[0]
        XCTAssertEqual(set.weight, 100)
        XCTAssertEqual(set.weightUnit, .kg)
        XCTAssertEqual(result.workouts[0].draft.exercises[0].name, "Squat")
    }

    func testHevyFailureZeroRepsAreKept() {
        let csv = """
        title,start_time,exercise_title,set_index,set_type,weight_lbs,reps
        Push Day,2025-03-28 17:00:00,Bench Press,0,normal,185,8
        Push Day,2025-03-28 17:00:00,Bench Press,1,failure,185,0
        """
        let result = try! XCTUnwrap(WorkoutCSVParser.parse(csv))
        let sets = result.workouts[0].draft.exercises[0].sets
        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets[1].weight, 185)
        XCTAssertEqual(sets[1].reps, 0)
        XCTAssertEqual(sets[1].notes, "Failure")
    }

    func testHevyFailureRowWithoutLoadIsKept() {
        let csv = """
        title,start_time,exercise_title,set_index,set_type,weight_lbs,reps
        Push Day,2025-03-28 17:00:00,Bench Press,0,failure,,
        """
        let result = try! XCTUnwrap(WorkoutCSVParser.parse(csv))
        let set = result.workouts[0].draft.exercises[0].sets[0]
        XCTAssertNil(set.weight)
        XCTAssertNil(set.reps)
        XCTAssertEqual(set.notes, "Failure")
    }

    func testStrongEquipmentSuffixIsStrippedFromExerciseName() {
        let csv = """
        Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
        2025-01-15 18:00:00,Leg Day,60m,Squat (Barbell),1,225,5,0,0,,,
        """
        let result = try! XCTUnwrap(WorkoutCSVParser.parse(csv))
        XCTAssertEqual(result.workouts[0].draft.exercises[0].name, "Squat")
    }

    func testDifferentEquipmentSuffixesStaySeparateExercises() {
        let csv = """
        Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
        2025-01-15 18:00:00,Leg Day,60m,Squat (Barbell),1,225,5,0,0,,,
        2025-01-15 18:00:00,Leg Day,60m,Squat (Dumbbell),1,50,10,0,0,,,
        """
        let result = try! XCTUnwrap(WorkoutCSVParser.parse(csv))
        let exercises = result.workouts[0].draft.exercises
        XCTAssertEqual(exercises.map(\.name), ["Squat", "Squat"])
        XCTAssertEqual(exercises[0].sets.map(\.weight), [225])
        XCTAssertEqual(exercises[1].sets.map(\.weight), [50])
        XCTAssertEqual(exercises[1].sets[0].reps, 10)
    }
}

@MainActor
final class WorkoutImportOrchestratorTests: MarbleTestCase {
    func testCSVWinsOverTextSplitter() {
        let csv = """
        title,start_time,exercise_title,set_index,weight_lbs,reps
        A,2025-01-15 18:00:00,Bench,0,185,8
        B,2025-01-16 18:00:00,Squat,0,225,5
        """
        let segments = WorkoutImportOrchestrator.segments(from: csv, referenceDate: now)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].kind, .hevyCSV)
        XCTAssertNotNil(segments[0].draft)
    }

    func testTextPasteSegmentsWithoutDraft() {
        let text = """
        3/5
        Bench 3x8 @ 185

        3/6
        Squat 5x5
        """
        let segments = WorkoutImportOrchestrator.segments(from: text, referenceDate: now)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].kind, .typedText)
        XCTAssertNil(segments[0].draft)
        XCTAssertNotEqual(
            WorkoutImportOrchestrator.externalID(for: segments[0]),
            WorkoutImportOrchestrator.externalID(for: segments[1])
        )
    }

    func testJoinSourcesDropsDuplicateCSVHeaders() {
        let first = """
        title,start_time,exercise_title,set_index,weight_lbs,reps
        A,2025-01-15 18:00:00,Bench,0,185,8
        """
        let second = """
        title,start_time,exercise_title,set_index,weight_lbs,reps
        B,2025-01-16 18:00:00,Squat,0,225,5
        """
        let joined = WorkoutImportOrchestrator.joinSources([first, second])
        let segments = WorkoutImportOrchestrator.segments(from: joined, referenceDate: now)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments.map(\.draft?.title), ["A", "B"])
    }
}
