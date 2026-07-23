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
