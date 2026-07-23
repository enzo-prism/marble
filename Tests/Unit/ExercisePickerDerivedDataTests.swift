import SwiftData
import XCTest
@testable import marble

final class ExercisePickerDerivedDataTests: MarbleTestCase {
    func testBuildDeduplicatesRecentsAndPartitionsFavorites() {
        let exercises = (0..<7).map { index in
            Exercise(
                name: "Exercise \(index)",
                category: .chest,
                metrics: .weightAndRepsRequired,
                defaultRestSeconds: 90,
                isFavorite: index == 1 || index == 5
            )
        }
        let recentEntries = [
            entry(for: exercises[3], minute: 6),
            entry(for: exercises[3], minute: 5),
            entry(for: exercises[2], minute: 4),
            entry(for: exercises[0], minute: 3),
            entry(for: exercises[4], minute: 2),
            entry(for: exercises[6], minute: 1),
            entry(for: exercises[1], minute: 0)
        ]
        let prescription = SprintPrescription(
            exerciseID: exercises[3].id,
            distance: 100,
            repetitionCount: 4,
            targetLowerSeconds: 12,
            targetUpperSeconds: 14
        )

        let result = ExercisePickerDerivedData.build(
            exercises: exercises,
            recentEntries: recentEntries,
            sprintPrescriptions: [prescription]
        )

        XCTAssertEqual(result.recents.map(\.id), [3, 2, 0, 4, 6].map { exercises[$0].id })
        XCTAssertEqual(result.favoriteRemainder.map(\.id), [exercises[1].id, exercises[5].id])
        XCTAssertTrue(result.allRemainder.isEmpty)
        XCTAssertEqual(result.prescriptions[exercises[3].id]?.id, prescription.id)
    }

    /// The bounded picker window replaced an unbounded all-history query, so
    /// its contract is that recents derived from the scoped rows match the
    /// full table. A window that never filled its limit *is* the full table.
    func testPickerRecentsWindowIsUsedAsIsWhenUnderLimit() {
        let exercises = (0..<3).map { index in
            Exercise(name: "Exercise \(index)", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
        }
        let window = (0..<10).map { entry(for: exercises[$0 % 3], minute: -$0) }

        let result = SetEntryQueries.entriesForPickerRecents(
            window: window,
            minimumDistinct: ExercisePickerDerivedData.recentLimit,
            in: makeInMemoryContext()
        )

        XCTAssertEqual(result.map(\.id), window.map(\.id))
    }

    /// A saturated window already spanning enough distinct exercises must be
    /// used directly. The context passed here is an *empty* store, so any
    /// accidental escalation would return no rows and fail the assertion.
    func testPickerRecentsSaturatedWindowWithEnoughDistinctExercisesSkipsEscalation() {
        let exercises = (0..<5).map { index in
            Exercise(name: "Exercise \(index)", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
        }
        let window = (0..<SetEntryQueries.pickerRecentScanLimit).map {
            entry(for: exercises[$0 % 5], minute: -$0)
        }

        let result = SetEntryQueries.entriesForPickerRecents(
            window: window,
            minimumDistinct: ExercisePickerDerivedData.recentLimit,
            in: makeInMemoryContext()
        )

        XCTAssertEqual(result.map(\.id), window.map(\.id))
    }

    /// The under-production case a fixed limit alone would get wrong: the
    /// newest `pickerRecentScanLimit` rows are all one exercise, with the
    /// other distinct exercises only in older history. Escalation must page
    /// deep enough that derived recents match the unbounded query it replaced.
    func testPickerRecentsEscalatesSaturatedSingleExerciseWindowToMatchFullHistory() throws {
        let context = makeInMemoryContext()
        let exercises = (0..<5).map { index in
            Exercise(name: "Exercise \(index)", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
        }
        exercises.forEach(context.insert)
        // Newest `pickerRecentScanLimit` sets: exercise 0 only.
        for index in 0..<SetEntryQueries.pickerRecentScanLimit {
            context.insert(entry(for: exercises[0], minute: -index))
        }
        // Older history introduces the remaining distinct exercises, most
        // recent first: 1, 2, 3, 4.
        for (offset, exercise) in exercises.dropFirst().enumerated() {
            context.insert(entry(for: exercise, minute: -(SetEntryQueries.pickerRecentScanLimit + offset + 1)))
        }
        try context.save()

        let window = try context.fetch(SetEntryQueries.recentEntriesForPicker)
        XCTAssertEqual(window.count, SetEntryQueries.pickerRecentScanLimit)
        XCTAssertTrue(window.allSatisfy { $0.exercise.id == exercises[0].id })

        let escalated = SetEntryQueries.entriesForPickerRecents(
            window: window,
            minimumDistinct: ExercisePickerDerivedData.recentLimit,
            in: context
        )
        let fromScoped = ExercisePickerDerivedData.build(
            exercises: exercises,
            recentEntries: escalated,
            sprintPrescriptions: []
        )
        let fullHistory = try context.fetch(FetchDescriptor<SetEntry>(
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        ))
        let fromFull = ExercisePickerDerivedData.build(
            exercises: exercises,
            recentEntries: fullHistory,
            sprintPrescriptions: []
        )

        XCTAssertEqual(fromScoped.recents.map(\.id), fromFull.recents.map(\.id))
        XCTAssertEqual(fromScoped.recents.map(\.id), exercises.map(\.id))
    }

    private func entry(for exercise: Exercise, minute: Int) -> SetEntry {
        let performedAt = MarbleTestCase.stableCalendar.date(byAdding: .minute, value: minute, to: now) ?? now
        return SetEntry(
            exercise: exercise,
            performedAt: performedAt,
            weight: 100,
            reps: 5,
            restAfterSeconds: 90,
            updatedAt: performedAt
        )
    }
}
