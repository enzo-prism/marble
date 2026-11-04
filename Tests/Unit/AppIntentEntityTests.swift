import SwiftData
import XCTest
@testable import marble

/// `ExerciseEntity` / `ExerciseQuery` — the surface Siri, Shortcuts and Spotlight
/// see. Every query routes through `AppIntentsSupport.resolvedContainer()`, so each
/// test points that shared slot at its own in-memory container.
@MainActor
final class AppIntentEntityTests: MarbleTestCase {
    override func tearDown() {
        MainActor.assumeIsolated {
            AppIntentsSupport.container = nil
        }
        super.tearDown()
    }

    // MARK: - entities(matching:)

    func testEntitiesMatchingStringIsCaseInsensitiveContains() async throws {
        let context = makeIntentContext()
        makeExercise(name: "Barbell Bench Press", category: .chest, in: context)
        makeExercise(name: "Close-Grip Bench", category: .triceps, in: context)
        makeExercise(name: "Deadlift", category: .back, in: context)
        try context.save()

        let matches = try await ExerciseQuery().entities(matching: "bench")

        XCTAssertEqual(matches.count, 2)
        XCTAssertFalse(matches.contains { $0.name == "Deadlift" })
        XCTAssertTrue(matches.contains { $0.name == "Barbell Bench Press" })
        XCTAssertTrue(matches.contains { $0.name == "Close-Grip Bench" })
    }

    func testEntitiesMatchingPrefersPrefixMatches() async throws {
        let context = makeIntentContext()
        makeExercise(name: "Close-Grip Bench", category: .triceps, in: context)
        makeExercise(name: "Bench Press", category: .chest, in: context)
        try context.save()

        let matches = try await ExerciseQuery().entities(matching: "BENCH")

        XCTAssertEqual(matches.map(\.name), ["Bench Press", "Close-Grip Bench"])
    }

    func testEntitiesMatchingEmptyStringReturnsNothing() async throws {
        let context = makeIntentContext()
        makeExercise(name: "Squat", category: .legs, in: context)
        try context.save()

        let matches = try await ExerciseQuery().entities(matching: "   ")

        XCTAssertTrue(matches.isEmpty)
    }

    // MARK: - suggestedEntities()

    func testSuggestedEntitiesPutsFavoritesFirstThenRecency() async throws {
        let context = makeIntentContext()

        // Favorites: one logged a week ago, one never logged.
        let favoriteRecent = makeExercise(name: "Ab Wheel", category: .core, isFavorite: true, in: context)
        makeExercise(name: "Zercher Squat", category: .legs, isFavorite: true, in: context)
        // Non-favorites: one logged yesterday, one logged a month ago.
        let recent = makeExercise(name: "Bench Press", category: .chest, in: context)
        let stale = makeExercise(name: "Deadlift", category: .back, in: context)

        logSet(for: favoriteRecent, at: now.addingTimeInterval(-7 * 86_400), in: context)
        logSet(for: recent, at: now.addingTimeInterval(-86_400), in: context)
        logSet(for: stale, at: now.addingTimeInterval(-30 * 86_400), in: context)
        try context.save()

        let suggestions = try await ExerciseQuery().suggestedEntities()

        XCTAssertEqual(
            suggestions.map(\.name),
            ["Ab Wheel", "Zercher Squat", "Bench Press", "Deadlift"],
            "Favorites must come first; within each group, most recently performed wins and never-performed sorts last."
        )
    }

    func testSuggestedEntitiesIsCappedAtSuggestionLimit() async throws {
        let context = makeIntentContext()
        for index in 0..<(ExerciseQuery.suggestionLimit + 5) {
            makeExercise(name: String(format: "Exercise %02d", index), category: .other, in: context)
        }
        try context.save()

        let suggestions = try await ExerciseQuery().suggestedEntities()

        XCTAssertEqual(suggestions.count, ExerciseQuery.suggestionLimit)
    }

    // MARK: - entities(for:)

    func testEntitiesForIdentifiersRoundTripsIDsAndDisplayFields() async throws {
        let context = makeIntentContext()
        let squat = makeExercise(name: "Back Squat", category: .quads, in: context)
        let curl = makeExercise(name: "Hammer Curl", category: .biceps, in: context)
        makeExercise(name: "Unrelated", category: .other, in: context)
        try context.save()

        // Order is the caller's, not the store's.
        let entities = try await ExerciseQuery().entities(for: [curl.id, squat.id])

        XCTAssertEqual(entities.map(\.id), [curl.id, squat.id])
        XCTAssertEqual(entities.map(\.name), ["Hammer Curl", "Back Squat"])
        XCTAssertEqual(
            entities.map(\.categoryName),
            [ExerciseCategory.biceps.displayName, ExerciseCategory.quads.displayName]
        )
    }

    func testEntitiesForUnknownIdentifierIsSkipped() async throws {
        let context = makeIntentContext()
        let squat = makeExercise(name: "Back Squat", category: .quads, in: context)
        try context.save()

        let entities = try await ExerciseQuery().entities(for: [UUID(), squat.id])

        XCTAssertEqual(entities.map(\.id), [squat.id])
    }

    // MARK: - Entity value semantics

    func testEntityMirrorsExerciseIdentityAndCategory() throws {
        let context = makeIntentContext()
        let exercise = makeExercise(name: "Farmer Carry", category: .power, in: context)
        try context.save()

        let entity = ExerciseEntity(exercise)

        XCTAssertEqual(entity.id, exercise.id)
        XCTAssertEqual(entity.name, "Farmer Carry")
        XCTAssertEqual(entity.categoryName, ExerciseCategory.power.displayName)
    }

    // MARK: - Properties Siri reads

    func testEntityCarriesPersonalBestsRecencyAndUsualRange() throws {
        let context = makeIntentContext()
        let bench = makeExercise(name: "Bench Press", category: .chest, isFavorite: true, in: context)
        let earlier = now.addingTimeInterval(-3 * 86_400)
        let later = now.addingTimeInterval(-86_400)
        logSet(for: bench, at: earlier, weight: 100, reps: 8, in: context)
        logSet(for: bench, at: later, weight: 120, reps: 3, in: context)
        try context.save()

        let entity = ExerciseEntity(bench)

        XCTAssertTrue(entity.isFavorite)
        XCTAssertEqual(entity.totalSets, 2)
        XCTAssertEqual(entity.lastPerformedAt, later)
        XCTAssertEqual(entity.heaviestSet, "120 lb × 3")
        XCTAssertEqual(entity.mostRepsSet, "8 reps at 100 lb")
        XCTAssertEqual(entity.usualRange, "100–120 lb, 3–8 reps")
    }

    func testNeverLoggedEntityHasNoBests() throws {
        let context = makeIntentContext()
        let squat = makeExercise(name: "Back Squat", category: .quads, in: context)
        try context.save()

        let entity = ExerciseEntity(squat)

        XCTAssertFalse(entity.isFavorite)
        XCTAssertEqual(entity.totalSets, 0)
        XCTAssertNil(entity.lastPerformedAt)
        XCTAssertNil(entity.heaviestSet)
        XCTAssertNil(entity.mostRepsSet)
        XCTAssertNil(entity.usualRange)
    }

    /// The batched builder (Spotlight reindex, every query) must agree with the
    /// per-exercise init, and must never leak one exercise's sets into another's.
    func testBatchedEntitiesMatchPerExerciseInitAndStayScoped() throws {
        let context = makeIntentContext()
        let bench = makeExercise(name: "Bench Press", category: .chest, in: context)
        let row = makeExercise(name: "Barbell Row", category: .back, in: context)
        logSet(for: bench, at: now.addingTimeInterval(-86_400), weight: 185, reps: 5, in: context)
        logSet(for: row, at: now.addingTimeInterval(-2 * 86_400), weight: 135, reps: 10, in: context)
        try context.save()

        let batched = ExerciseEntity.entities(for: [bench, row], in: context)
        let single = [ExerciseEntity(bench), ExerciseEntity(row)]

        XCTAssertEqual(batched.map(\.id), [bench.id, row.id])
        XCTAssertEqual(batched.map(\.heaviestSet), single.map(\.heaviestSet))
        XCTAssertEqual(batched.map(\.totalSets), [1, 1])
        XCTAssertEqual(batched.map(\.heaviestSet), ["185 lb × 5", "135 lb × 10"])
    }

    // MARK: - Fixtures

    private func makeIntentContext() -> ModelContext {
        let container = makeInMemoryContainer()
        // `register` (not a bare assignment) because the intents now inject the
        // container through `@Dependency`/`AppDependencyManager`, which only the
        // registration path populates.
        AppIntentsSupport.register(container: container)
        return container.mainContext
    }

    @discardableResult
    private func makeExercise(
        name: String,
        category: ExerciseCategory,
        isFavorite: Bool = false,
        in context: ModelContext
    ) -> Exercise {
        let exercise = Exercise(
            name: name,
            category: category,
            metrics: .weightAndRepsRequired,
            defaultRestSeconds: 90,
            isFavorite: isFavorite,
            createdAt: now
        )
        context.insert(exercise)
        return exercise
    }

    private func logSet(
        for exercise: Exercise,
        at date: Date,
        weight: Double = 100,
        reps: Int = 5,
        in context: ModelContext
    ) {
        let entry = SetEntry(
            exercise: exercise,
            performedAt: date,
            weight: weight,
            weightUnit: .lb,
            reps: reps,
            restAfterSeconds: 90,
            createdAt: date,
            updatedAt: date
        )
        context.insert(entry)
    }
}
