import SwiftData
import SwiftUI
import XCTest
@testable import marble

final class ExerciseProgressSnapshotTests: SnapshotTestCase {
    func testExerciseProgressTooltip() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)

        let exercise = SnapshotFixtures.exercise(named: "Bench Press", in: context)
        let entries = SetEntryQueries.entries(for: exercise.id, range: .thirtyDays, in: context)
        let points = ExerciseProgressBuilder.buildPoints(entries: entries, exercise: exercise, range: .thirtyDays)

        let view = ExerciseProgressChartFixture(points: points)
        assertSnapshot(view, named: "ExerciseProgress_Tooltip")
    }
}

private struct ExerciseProgressChartFixture: View {
    let points: [ExerciseProgressPoint]

    var body: some View {
        ExerciseProgressChart(
            points: points,
            isScrubbing: .constant(false),
            initialSelectedDate: points.last?.date
        ) { _ in }
        .padding(MarbleLayout.pagePadding)
    }
}
