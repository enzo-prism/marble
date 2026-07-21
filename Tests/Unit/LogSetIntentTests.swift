import SwiftData
import XCTest
@testable import marble

/// `LogSetIntent` writes real rows, so these assert against the store rather than
/// the spoken dialog: a friendly sentence over a corrupted set is the failure mode
/// this suite exists to catch.
@MainActor
final class LogSetIntentTests: MarbleTestCase {
    override func tearDown() {
        MainActor.assumeIsolated {
            AppIntentsSupport.container = nil
        }
        super.tearDown()
    }

    // MARK: - Inheriting from history

    func testOmittedValuesAreInheritedFromTheLastSetOfThatExercise() async throws {
        let context = makeIntentContext()
        let bench = makeExercise(name: "Bench Press", category: .chest, in: context)
        // A different exercise logged more recently must not leak into the defaults.
        let squat = makeExercise(name: "Back Squat", category: .quads, in: context)
        logSet(for: bench, weight: 185, unit: .lb, reps: 5, at: now.addingTimeInterval(-3_600), in: context)
        logSet(for: squat, weight: 315, unit: .lb, reps: 3, at: now.addingTimeInterval(-60), in: context)
        try context.save()

        _ = try await perform(exercise: bench)

        let logged = try newestEntry(for: bench, in: context)
        XCTAssertEqual(logged.weight, 185)
        XCTAssertEqual(logged.reps, 5)
        XCTAssertEqual(logged.weightUnit, .lb)
        XCTAssertEqual(logged.performedAt, now)
        XCTAssertEqual(try count(SetEntry.self, in: context), 3)
    }

    func testExplicitValuesWinOverHistory() async throws {
        let context = makeIntentContext()
        let bench = makeExercise(name: "Bench Press", category: .chest, in: context)
        logSet(for: bench, weight: 185, unit: .lb, reps: 5, at: now.addingTimeInterval(-3_600), in: context)
        try context.save()

        _ = try await perform(exercise: bench, reps: 8, weight: 100, unit: .kg)

        let logged = try newestEntry(for: bench, in: context)
        XCTAssertEqual(logged.reps, 8)
        XCTAssertEqual(logged.weight, 100)
        XCTAssertEqual(logged.weightUnit, .kg)
    }

    /// A weight inherited from history in one unit, requested in another, must be
    /// *converted*, never relabelled. Relabelling is the lb/kg bug class this repo
    /// has shipped four times.
    func testInheritedWeightIsConvertedWhenAnotherUnitIsRequested() async throws {
        let context = makeIntentContext()
        let bench = makeExercise(name: "Bench Press", category: .chest, in: context)
        logSet(for: bench, weight: 100, unit: .lb, reps: 5, at: now.addingTimeInterval(-3_600), in: context)
        try context.save()

        _ = try await perform(exercise: bench, unit: .kg)

        let logged = try newestEntry(for: bench, in: context)
        XCTAssertEqual(logged.weightUnit, .kg)
        XCTAssertEqual(try XCTUnwrap(logged.weight), 45.359237, accuracy: 0.0001)
        XCTAssertEqual(
            PersonalRecords.kilograms(try XCTUnwrap(logged.weight), unit: .kg),
            PersonalRecords.kilograms(100, unit: .lb),
            accuracy: 0.0001,
            "The set must weigh the same in kg after the unit change."
        )
    }

    // MARK: - Dumbbell-pair doubling

    /// A spoken weight is the *input* weight — one dumbbell — exactly like the field
    /// in AddSetView. Storage keeps total resistance, so it must be doubled once.
    func testSpokenWeightForDumbbellPairIsDoubledIntoStorage() async throws {
        let context = makeIntentContext()
        let curl = makeExercise(
            name: "Dumbbell Curl",
            category: .biceps,
            resistanceTrackingStyle: .singleDumbbellPair,
            in: context
        )
        try context.save()

        _ = try await perform(exercise: curl, reps: 10, weight: 40)

        let logged = try newestEntry(for: curl, in: context)
        XCTAssertEqual(logged.weight, 80, "40 per hand is 80 of total resistance.")
        XCTAssertEqual(curl.displayedWeightInput(from: logged.weight), 40)
    }

    /// The inherited path must round-trip, not compound: reading the stored 80 back
    /// out (÷2) before storing it again (×2) has to land on 80, not 160.
    func testInheritedDumbbellPairWeightRoundTripsInsteadOfDoubling() async throws {
        let context = makeIntentContext()
        let curl = makeExercise(
            name: "Dumbbell Curl",
            category: .biceps,
            resistanceTrackingStyle: .singleDumbbellPair,
            in: context
        )
        logSet(for: curl, weight: 80, unit: .lb, reps: 10, at: now.addingTimeInterval(-3_600), in: context)
        try context.save()

        _ = try await perform(exercise: curl)

        let logged = try newestEntry(for: curl, in: context)
        XCTAssertEqual(logged.weight, 80)
        XCTAssertEqual(logged.reps, 10)
    }

    /// Two consecutive voice logs must not drift — the classic compounding signature.
    func testRepeatedInheritedDumbbellLogsAreStable() async throws {
        let context = makeIntentContext()
        let curl = makeExercise(
            name: "Dumbbell Curl",
            category: .biceps,
            resistanceTrackingStyle: .singleDumbbellPair,
            in: context
        )
        logSet(for: curl, weight: 80, unit: .lb, reps: 10, at: now.addingTimeInterval(-3_600), in: context)
        try context.save()

        _ = try await perform(exercise: curl)
        _ = try await perform(exercise: curl)

        let weights = try entries(for: curl, in: context).map(\.weight)
        XCTAssertEqual(weights, [80, 80, 80])
    }

    // MARK: - Refusing to write a bad row

    func testNoHistoryAndNoValuesReturnsDialogWithoutInserting() async throws {
        let context = makeIntentContext()
        let bench = makeExercise(name: "Bench Press", category: .chest, in: context)
        try context.save()

        _ = try await perform(exercise: bench)

        XCTAssertEqual(
            try count(SetEntry.self, in: context),
            0,
            "A required weight and reps with nothing to inherit must not produce a set."
        )
    }

    func testPartialValuesWithNoHistoryStillRefuseToWrite() async throws {
        let context = makeIntentContext()
        let bench = makeExercise(name: "Bench Press", category: .chest, in: context)
        try context.save()

        // Reps supplied, weight missing, and weight is required for this exercise.
        _ = try await perform(exercise: bench, reps: 5)

        XCTAssertEqual(try count(SetEntry.self, in: context), 0)
    }

    func testMissingExerciseDoesNotInsertAnything() async throws {
        let context = makeIntentContext()
        try context.save()

        let ghost = ExerciseEntity(id: UUID(), name: "Ghost Press", categoryName: "Chest")
        let intent = LogSetIntent()
        intent.exercise = ghost
        _ = try await intent.perform()

        XCTAssertEqual(try count(SetEntry.self, in: context), 0)
    }

    func testExerciseWithNoRequiredMetricsLogsEvenWithoutHistory() async throws {
        let context = makeIntentContext()
        let sauna = makeExercise(
            name: "Sauna",
            category: .recover,
            metrics: ExerciseMetricsProfile(weight: .none, reps: .none, distance: .none, durationSeconds: .optional),
            in: context
        )
        try context.save()

        _ = try await perform(exercise: sauna)

        XCTAssertEqual(try count(SetEntry.self, in: context), 1)
    }

    // MARK: - Sprint goal freeze

    func testSprintSnapshotIsFrozenFromTheCurrentPrescription() async throws {
        let context = makeIntentContext()
        let sprint = makeExercise(
            name: "60m Sprint",
            category: .run,
            metrics: .distanceAndDurationRequired,
            in: context
        )
        logSet(
            for: sprint,
            weight: nil,
            unit: .lb,
            reps: nil,
            distance: 60,
            durationSeconds: 8,
            at: now.addingTimeInterval(-600),
            in: context
        )
        let prescription = SprintPrescription(
            exerciseID: sprint.id,
            distance: 60,
            repetitionCount: 6,
            targetLowerSeconds: 7,
            targetUpperSeconds: 8,
            createdAt: now,
            updatedAt: now
        )
        context.insert(prescription)
        try context.save()

        _ = try await perform(exercise: sprint)

        let logged = try newestEntry(for: sprint, in: context)
        let loggedID = logged.id
        let snapshots = try context.fetch(
            FetchDescriptor<SprintGoalSnapshot>(predicate: #Predicate { $0.setEntryID == loggedID })
        )
        let snapshot = try XCTUnwrap(snapshots.first, "The new rep must carry its own frozen goal.")
        XCTAssertEqual(snapshot.exerciseID, sprint.id)
        XCTAssertEqual(snapshot.distance, 60)
        XCTAssertEqual(snapshot.repetitionCount, 6)
        XCTAssertEqual(snapshot.targetLowerSeconds, 7)
        XCTAssertEqual(snapshot.targetUpperSeconds, 8)
        // Distance and duration are inherited so the rep is scoreable at all.
        XCTAssertEqual(logged.distance, 60)
        XCTAssertEqual(logged.durationSeconds, 8)
    }

    func testNonSprintExerciseGetsNoSnapshot() async throws {
        let context = makeIntentContext()
        let bench = makeExercise(name: "Bench Press", category: .chest, in: context)
        logSet(for: bench, weight: 185, unit: .lb, reps: 5, at: now.addingTimeInterval(-3_600), in: context)
        try context.save()

        _ = try await perform(exercise: bench)

        XCTAssertEqual(try count(SprintGoalSnapshot.self, in: context), 0)
    }

    // MARK: - Session grouping

    func testLoggedSetJoinsTheRunningWorkout() async throws {
        let context = makeIntentContext()
        let bench = makeExercise(name: "Bench Press", category: .chest, in: context)
        logSet(for: bench, weight: 185, unit: .lb, reps: 5, at: now.addingTimeInterval(-3_600), in: context)
        let session = WorkoutSession(title: "Push", startedAt: now.addingTimeInterval(-1_800))
        context.insert(session)
        try context.save()

        _ = try await perform(exercise: bench)

        let logged = try newestEntry(for: bench, in: context)
        XCTAssertEqual(session.entries.map(\.id), [logged.id])
    }

    func testLoggedSetWithoutASessionStaysUngrouped() async throws {
        let context = makeIntentContext()
        let bench = makeExercise(name: "Bench Press", category: .chest, in: context)
        logSet(for: bench, weight: 185, unit: .lb, reps: 5, at: now.addingTimeInterval(-3_600), in: context)
        try context.save()

        _ = try await perform(exercise: bench)

        XCTAssertEqual(try count(WorkoutSession.self, in: context), 0)
        XCTAssertEqual(try count(SetEntry.self, in: context), 2)
    }

    // MARK: - Unit conversion helper

    func testConvertUsesTheCanonicalKilogramFactor() {
        XCTAssertEqual(LogSetIntent.convert(100, from: .lb, to: .lb), 100)
        XCTAssertEqual(LogSetIntent.convert(100, from: .lb, to: .kg), 45.359237, accuracy: 0.0001)
        XCTAssertEqual(LogSetIntent.convert(45.359237, from: .kg, to: .lb), 100, accuracy: 0.0001)
    }

    // MARK: - Fixtures

    private func makeIntentContext() -> ModelContext {
        let container = makeInMemoryContainer()
        AppIntentsSupport.container = container
        return container.mainContext
    }

    @discardableResult
    private func perform(
        exercise: Exercise,
        reps: Int? = nil,
        weight: Double? = nil,
        unit: WeightUnit? = nil
    ) async throws -> Bool {
        let intent = LogSetIntent()
        intent.exercise = ExerciseEntity(exercise)
        intent.reps = reps
        intent.weight = weight
        intent.unit = unit.map(WeightUnitAppEnum.init)
        _ = try await intent.perform()
        return true
    }

    @discardableResult
    private func makeExercise(
        name: String,
        category: ExerciseCategory,
        metrics: ExerciseMetricsProfile = .weightAndRepsRequired,
        resistanceTrackingStyle: ResistanceTrackingStyle = .totalLoad,
        in context: ModelContext
    ) -> Exercise {
        let exercise = Exercise(
            name: name,
            category: category,
            resistanceTrackingStyle: resistanceTrackingStyle,
            metrics: metrics,
            defaultRestSeconds: 90,
            createdAt: now
        )
        context.insert(exercise)
        return exercise
    }

    private func logSet(
        for exercise: Exercise,
        weight: Double?,
        unit: WeightUnit,
        reps: Int?,
        distance: Double? = nil,
        durationSeconds: Int? = nil,
        at date: Date,
        in context: ModelContext
    ) {
        let entry = SetEntry(
            exercise: exercise,
            performedAt: date,
            weight: weight,
            weightUnit: unit,
            reps: reps,
            distance: distance,
            durationSeconds: durationSeconds,
            restAfterSeconds: 90,
            createdAt: date,
            updatedAt: date
        )
        context.insert(entry)
    }

    private func entries(for exercise: Exercise, in context: ModelContext) throws -> [SetEntry] {
        let exerciseID = exercise.id
        return try context.fetch(
            FetchDescriptor<SetEntry>(
                predicate: #Predicate { $0.exercise.id == exerciseID },
                sortBy: [SortDescriptor(\.performedAt)]
            )
        )
    }

    private func newestEntry(for exercise: Exercise, in context: ModelContext) throws -> SetEntry {
        try XCTUnwrap(entries(for: exercise, in: context).last)
    }

    private func count<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }
}
