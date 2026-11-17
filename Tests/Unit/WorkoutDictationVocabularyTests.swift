import SwiftData
import XCTest
@testable import marble

/// Hardware-free checks for live dictation: the progressive transcript model and
/// the contextual vocabulary handed to the speech analyzer.
@MainActor
final class WorkoutDictationVocabularyTests: MarbleTestCase {
    // MARK: - Progressive transcript

    func testVolatileTextIsReplacedThenSettledByFinalText() {
        var transcript = WorkoutDictationTranscript()
        transcript.apply("bench", isFinal: false)
        transcript.apply("bench press three", isFinal: false)
        XCTAssertEqual(transcript.finalized, "")
        XCTAssertEqual(transcript.volatile, "bench press three")
        XCTAssertEqual(transcript.combined, "bench press three")

        transcript.apply(" Bench press 3x8 ", isFinal: true)
        XCTAssertEqual(transcript.finalized, "Bench press 3x8")
        XCTAssertEqual(transcript.volatile, "")

        transcript.apply("at one", isFinal: false)
        XCTAssertEqual(transcript.combined, "Bench press 3x8 at one")
        transcript.apply("at 185 pounds", isFinal: true)
        XCTAssertEqual(transcript.combined, "Bench press 3x8 at 185 pounds")
    }

    func testCommittingKeepsUnfinalizedWords() {
        var transcript = WorkoutDictationTranscript()
        transcript.apply("Squat 5x5", isFinal: true)
        transcript.apply("at 225", isFinal: false)
        transcript.commitVolatile()
        XCTAssertEqual(transcript.finalized, "Squat 5x5 at 225")
        XCTAssertEqual(transcript.volatile, "")
        transcript.commitVolatile()
        XCTAssertEqual(transcript.finalized, "Squat 5x5 at 225")
    }

    func testEmptyResultsDoNotAddSpacing() {
        var transcript = WorkoutDictationTranscript()
        transcript.apply("   ", isFinal: true)
        transcript.apply("Rows", isFinal: true)
        transcript.apply("", isFinal: true)
        XCTAssertEqual(transcript.finalized, "Rows")
    }

    // MARK: - Vocabulary

    func testRecentNamesComeFirstAndDuplicatesAreDropped() {
        let strings = WorkoutDictationVocabulary.strings(
            recentExerciseNames: ["Front Squat", "Bench Press", "front squat", "Front Squat"],
            libraryExerciseNames: ["Bench Press", "Barbell Row", "  ", "Zercher Squat"]
        )
        XCTAssertEqual(Array(strings.prefix(4)), ["Front Squat", "Bench Press", "Barbell Row", "Zercher Squat"])
    }

    func testExerciseNamesAreCappedButJargonIsAlwaysIncluded() {
        let library = (0..<500).map { "Movement \($0)" }
        let strings = WorkoutDictationVocabulary.strings(recentExerciseNames: [], libraryExerciseNames: library, limit: 100)
        XCTAssertEqual(strings.filter { $0.hasPrefix("Movement") }.count, 100)
        for term in ["RDL", "DB", "BB", "KB", "AMRAP", "EMOM", "RPE", "PR", "superset", "Bulgarian split squat"] {
            XCTAssertTrue(strings.contains(term), term)
        }
    }

    func testJargonAlreadyInTheLibraryIsNotRepeated() {
        let strings = WorkoutDictationVocabulary.strings(recentExerciseNames: ["Bulgarian Split Squat"], libraryExerciseNames: [])
        XCTAssertEqual(strings.filter { $0.lowercased() == "bulgarian split squat" }, ["Bulgarian Split Squat"])
    }

    func testStoreVocabularyOrdersByMostRecentlyLoggedThenFavorites() throws {
        let context = makeInMemoryContext()
        func exercise(_ name: String, favorite: Bool = false) -> Exercise {
            let value = Exercise(name: name, category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90, createdAt: now)
            value.isFavorite = favorite
            context.insert(value)
            return value
        }
        let bench = exercise("Bench Press")
        let squat = exercise("Back Squat")
        _ = exercise("Arnold Press")
        _ = exercise("Zottman Curl", favorite: true)
        context.insert(SetEntry(exercise: bench, performedAt: now.addingTimeInterval(-7_200), weight: 185, reps: 5, restAfterSeconds: 90))
        context.insert(SetEntry(exercise: squat, performedAt: now.addingTimeInterval(-60), weight: 225, reps: 5, restAfterSeconds: 90))
        try context.save()

        let strings = WorkoutDictationVocabulary.strings(in: context)

        XCTAssertEqual(Array(strings.prefix(4)), ["Back Squat", "Bench Press", "Zottman Curl", "Arnold Press"])
        XCTAssertTrue(strings.contains("AMRAP"))
    }
}
