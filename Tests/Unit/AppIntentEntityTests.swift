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

    // MARK: - Fixtures

    private func makeIntentContext() -> ModelContext {
        let container = makeInMemoryContainer()
        AppIntentsSupport.container = container
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

    private func logSet(for exercise: Exercise, at date: Date, in context: ModelContext) {
        let entry = SetEntry(
            exercise: exercise,
            performedAt: date,
            weight: 100,
            weightUnit: .lb,
            reps: 5,
            restAfterSeconds: 90,
            createdAt: date,
            updatedAt: date
        )
        context.insert(entry)
    }
}
