import XCTest
import SwiftData
import UIKit
@testable import marble

final class ExerciseIconTests: MarbleTestCase {
    func testLegacyMetricsProfileDecodingDefaultsDistanceToNone() throws {
        let data = """
        {"weight":"required","reps":"required","durationSeconds":"none"}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ExerciseMetricsProfile.self, from: data)

        XCTAssertEqual(decoded.weight, .required)
        XCTAssertEqual(decoded.reps, .required)
        XCTAssertEqual(decoded.distance, .none)
        XCTAssertEqual(decoded.durationSeconds, .none)
    }

    func testSingleDumbbellResistanceStyleStoresTotalLoadAndDisplaysPerHand() {
        let exercise = Exercise(
            name: "DB Incline Press",
            category: .chest,
            resistanceTrackingStyle: .singleDumbbellPair,
            metrics: .weightAndRepsRequired,
            defaultRestSeconds: 90
        )

        XCTAssertEqual(exercise.weightInputTitle, "Single dumbbell")
        XCTAssertEqual(exercise.storedWeight(from: 25), 50)
        XCTAssertEqual(exercise.displayedWeightInput(from: 50), 25)
        XCTAssertEqual(exercise.formattedWeightSummary(50, unit: .lb), "25 lb each (50 lb total)")
    }

    func testConfigurationSummaryIncludesLoadStyleAndDistanceUnit() {
        let exercise = Exercise(
            name: "Sprint",
            category: .power,
            resistanceTrackingStyle: .singleDumbbellPair,
            preferredDistanceUnit: .yards,
            metrics: ExerciseMetricsProfile(weight: .required, reps: .none, distance: .required, durationSeconds: .required),
            defaultRestSeconds: 60
        )

        XCTAssertEqual(
            exercise.configurationSummaryText,
            "Required: load, distance, and duration · Enter one dumbbell · Distance yd · Rest 1m"
        )
    }

    func testDisplayIconDefaultsToCategorySymbol() {
        let exercise = Exercise(
            name: "Bench Press",
            category: .chest,
            metrics: .weightAndRepsRequired,
            defaultRestSeconds: 90
        )

        XCTAssertEqual(exercise.displayIcon, .symbol(ExerciseCategory.chest.symbolName))
    }

    func testDisplayIconUsesCustomEmojiWhenPresent() {
        let exercise = Exercise(
            name: "Pull Ups",
            category: .bar,
            customIconEmoji: "💪",
            metrics: .repsOnlyRequired,
            defaultRestSeconds: 90
        )

        XCTAssertEqual(exercise.displayIcon, .emoji("💪"))
    }

    func testDisplayIconFallsBackWhenCustomEmojiIsInvalid() {
        let exercise = Exercise(
            name: "Tempo Squat",
            category: .legs,
            customIconEmoji: "tempo",
            metrics: .weightAndRepsRequired,
            defaultRestSeconds: 120
        )

        XCTAssertEqual(exercise.displayIcon, .symbol(ExerciseCategory.legs.symbolName))
    }

    func testCategoryIconsAlwaysResolveToSupportedSystemSymbol() {
        for category in ExerciseCategory.allCases {
            XCTAssertNotNil(
                UIImage(systemName: category.symbolName),
                "Expected \(category.displayName) to resolve to a supported SF Symbol"
            )
        }
    }

    func testFirstExerciseEmojiExtractsFirstValidEmojiCluster() {
        XCTAssertEqual("🔥💪".firstExerciseEmoji, "🔥")
        XCTAssertEqual("Lift 💪 hard".firstExerciseEmoji, "💪")
        XCTAssertEqual("👨‍👩‍👧‍👦 family".firstExerciseEmoji, "👨‍👩‍👧‍👦")
        XCTAssertEqual("Warm up 🏋️‍♂️ today".firstExerciseEmoji, "🏋️‍♂️")
        XCTAssertEqual("Flag 🇺🇸 finish".firstExerciseEmoji, "🇺🇸")
        XCTAssertEqual("Choice 1️⃣ first".firstExerciseEmoji, "1️⃣")
        XCTAssertNil("Bench Press".firstExerciseEmoji)
    }

    func testInitializerSanitizesCustomEmojiToFirstValidEmoji() {
        let exercise = Exercise(
            name: "Ring Row",
            category: .bar,
            customIconEmoji: "Lift 💪🔥",
            metrics: .repsOnlyRequired,
            defaultRestSeconds: 75
        )

        XCTAssertEqual(exercise.customIconEmoji, "💪")
        XCTAssertEqual(exercise.displayIcon, .emoji("💪"))
    }

    func testDisplayIconSupportsLegacyUnsanitizedEmojiValues() {
        let exercise = Exercise(
            name: "Sauna",
            category: .recover,
            metrics: .durationOnlyRequired,
            defaultRestSeconds: 0
        )

        exercise.customIconEmoji = "Recovery 🧖 today"

        XCTAssertEqual(exercise.sanitizedCustomIconEmoji, "🧖")
        XCTAssertEqual(exercise.displayIcon, .emoji("🧖"))
    }

    func testSetCustomIconEmojiSanitizesToFirstValidEmoji() {
        let exercise = Exercise(
            name: "Farmer Carry",
            category: .power,
            metrics: .weightAndRepsRequired,
            defaultRestSeconds: 60
        )

        exercise.setCustomIconEmoji("Grip 🧤🔥")

        XCTAssertEqual(exercise.customIconEmoji, "🧤")
        XCTAssertEqual(exercise.displayIcon, .emoji("🧤"))
    }

    func testSetCustomIconEmojiClearsInvalidIconText() {
        let exercise = Exercise(
            name: "Reverse Lunge",
            category: .legs,
            customIconEmoji: "🦵",
            metrics: .weightAndRepsRequired,
            defaultRestSeconds: 90
        )

        exercise.setCustomIconEmoji("not an emoji")

        XCTAssertNil(exercise.customIconEmoji)
        XCTAssertEqual(exercise.displayIcon, .symbol(ExerciseCategory.legs.symbolName))
    }

    func testCustomEmojiPersistsAcrossSwiftDataSaveAndFetch() throws {
        let context = makeInMemoryContext()
        let exercise = Exercise(
            name: "Aardvark Step Up",
            category: .legs,
            customIconEmoji: "🦵",
            metrics: .repsOnlyRequired,
            defaultRestSeconds: 60
        )

        context.insert(exercise)
        try context.save()

        let fetched = try XCTUnwrap(
            context.fetch(
                FetchDescriptor<Exercise>(
                    predicate: #Predicate { $0.name == "Aardvark Step Up" }
                )
            ).first
        )

        XCTAssertEqual(fetched.customIconEmoji, "🦵")
        XCTAssertEqual(fetched.displayIcon, .emoji("🦵"))
    }

    func testUpdatingCustomEmojiPersistsLatestChoice() throws {
        let context = makeInMemoryContext()
        let exercise = Exercise(
            name: "Cable Row Custom",
            category: .back,
            customIconEmoji: "💪",
            metrics: .weightAndRepsRequired,
            defaultRestSeconds: 75
        )

        context.insert(exercise)
        try context.save()

        exercise.customIconEmoji = "⚡️"
        try context.save()

        let fetched = try XCTUnwrap(
            context.fetch(
                FetchDescriptor<Exercise>(
                    predicate: #Predicate { $0.name == "Cable Row Custom" }
                )
            ).first
        )

        XCTAssertEqual(fetched.customIconEmoji, "⚡️")
        XCTAssertEqual(fetched.displayIcon, .emoji("⚡️"))
    }

    func testClearingCustomEmojiFallsBackToCategoryIconAfterSave() throws {
        let context = makeInMemoryContext()
        let exercise = Exercise(
            name: "Leg Press Custom",
            category: .legs,
            customIconEmoji: "🔥",
            metrics: .weightAndRepsRequired,
            defaultRestSeconds: 90
        )

        context.insert(exercise)
        try context.save()

        exercise.customIconEmoji = nil
        try context.save()

        let fetched = try XCTUnwrap(
            context.fetch(
                FetchDescriptor<Exercise>(
                    predicate: #Predicate { $0.name == "Leg Press Custom" }
                )
            ).first
        )

        XCTAssertNil(fetched.customIconEmoji)
        XCTAssertEqual(fetched.displayIcon, .symbol(ExerciseCategory.legs.symbolName))
    }
}
