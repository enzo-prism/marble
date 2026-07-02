import XCTest
@testable import marble

final class ExerciseProgressBuilderTests: MarbleTestCase {
    private let calendar = MarbleTestCase.stableCalendar
    private let timesSymbol = "\u{00D7}"

    func testWeightedProgressUsesHeaviestSetInsteadOfVolume() {
        let exercise = Exercise(
            name: "Bench",
            category: .chest,
            metrics: .weightAndRepsRequired,
            defaultRestSeconds: 90
        )
        let first = SetEntry(
            exercise: exercise,
            performedAt: date(daysFromNow: 0, hour: 9, minute: 0),
            weight: 100,
            weightUnit: .lb,
            reps: 5,
            durationSeconds: nil,
            difficulty: 8,
            restAfterSeconds: 90
        )
        let second = SetEntry(
            exercise: exercise,
            performedAt: date(daysFromNow: 0, hour: 9, minute: 20),
            weight: 90,
            weightUnit: .lb,
            reps: 8,
            durationSeconds: nil,
            difficulty: 8,
            restAfterSeconds: 90
        )

        let points = ExerciseProgressBuilder.buildPoints(
            entries: [first, second],
            exercise: exercise,
            range: .all,
            calendar: calendar
        )

        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.bestSetSummary, "100 lb \(timesSymbol) 5")
        XCTAssertEqual(points.first?.score, 100.0)
    }

    func testLiftBestsTrackHeaviestAndMostRepsSeparately() {
        let exercise = Exercise(
            name: "Power Clean",
            category: .power,
            metrics: .weightAndRepsRequired,
            defaultRestSeconds: 180
        )
        let heaviest = SetEntry(
            exercise: exercise,
            performedAt: date(daysFromNow: -1, hour: 9, minute: 0),
            weight: 185,
            weightUnit: .lb,
            reps: 2,
            durationSeconds: nil,
            difficulty: 9,
            restAfterSeconds: 180
        )
        let mostReps = SetEntry(
            exercise: exercise,
            performedAt: date(daysFromNow: 0, hour: 9, minute: 0),
            weight: 155,
            weightUnit: .lb,
            reps: 5,
            durationSeconds: nil,
            difficulty: 8,
            restAfterSeconds: 180
        )
        let middle = SetEntry(
            exercise: exercise,
            performedAt: date(daysFromNow: 0, hour: 9, minute: 20),
            weight: 175,
            weightUnit: .lb,
            reps: 3,
            durationSeconds: nil,
            difficulty: 8,
            restAfterSeconds: 180
        )

        let bests = ExerciseProgressBuilder.buildLiftBests(
            entries: [middle, mostReps, heaviest],
            exercise: exercise,
            range: .all
        )

        XCTAssertEqual(bests?.exerciseName, "Power Clean")
        XCTAssertEqual(bests?.heaviestEntry?.id, heaviest.id)
        XCTAssertEqual(bests?.mostRepsEntry?.id, mostReps.id)
    }

    func testRangeFiltersOldEntries() {
        let exercise = Exercise(
            name: "Squat",
            category: .legs,
            metrics: .weightAndRepsRequired,
            defaultRestSeconds: 120
        )
        let recent = SetEntry(
            exercise: exercise,
            performedAt: date(daysFromNow: -2, hour: 10, minute: 0),
            weight: 200,
            weightUnit: .lb,
            reps: 3,
            durationSeconds: nil,
            difficulty: 8,
            restAfterSeconds: 120
        )
        let older = SetEntry(
            exercise: exercise,
            performedAt: date(daysFromNow: -10, hour: 10, minute: 0),
            weight: 180,
            weightUnit: .lb,
            reps: 5,
            durationSeconds: nil,
            difficulty: 8,
            restAfterSeconds: 120
        )

        let points = ExerciseProgressBuilder.buildPoints(
            entries: [recent, older],
            exercise: exercise,
            range: .sevenDays,
            calendar: calendar
        )

        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.date, calendar.startOfDay(for: recent.performedAt))
    }

    func testBestSetSummaryFormattingByMetric() {
        let weighted = Exercise(
            name: "Deadlift",
            category: .back,
            metrics: .weightAndRepsRequired,
            defaultRestSeconds: 120
        )
        let weightedEntry = SetEntry(
            exercise: weighted,
            performedAt: date(daysFromNow: 0, hour: 8, minute: 0),
            weight: 185,
            weightUnit: .lb,
            reps: 5,
            durationSeconds: nil,
            difficulty: 8,
            restAfterSeconds: 120
        )

        let repsOnly = Exercise(
            name: "Plank",
            category: .core,
            metrics: .repsOnlyRequired,
            defaultRestSeconds: 45
        )
        let repsEntry = SetEntry(
            exercise: repsOnly,
            performedAt: date(daysFromNow: 0, hour: 9, minute: 0),
            weight: nil,
            weightUnit: .lb,
            reps: 12,
            durationSeconds: nil,
            difficulty: 7,
            restAfterSeconds: 45
        )

        let durationOnly = Exercise(
            name: "Sauna",
            category: .recover,
            metrics: .durationOnlyRequired,
            defaultRestSeconds: 0
        )
        let durationEntry = SetEntry(
            exercise: durationOnly,
            performedAt: date(daysFromNow: 0, hour: 10, minute: 0),
            weight: nil,
            weightUnit: .lb,
            reps: nil,
            durationSeconds: 510,
            difficulty: 1,
            restAfterSeconds: 0
        )

        let weightedPoint = ExerciseProgressBuilder.buildPoints(
            entries: [weightedEntry],
            exercise: weighted,
            range: .all,
            calendar: calendar
        ).first
        XCTAssertEqual(weightedPoint?.bestSetSummary, "185 lb \(timesSymbol) 5")

        let repsPoint = ExerciseProgressBuilder.buildPoints(
            entries: [repsEntry],
            exercise: repsOnly,
            range: .all,
            calendar: calendar
        ).first
        XCTAssertEqual(repsPoint?.bestSetSummary, "12 reps")

        let durationPoint = ExerciseProgressBuilder.buildPoints(
            entries: [durationEntry],
            exercise: durationOnly,
            range: .all,
            calendar: calendar
        ).first
        XCTAssertEqual(durationPoint?.bestSetSummary, "8:30")
    }

    private func date(daysFromNow: Int, hour: Int, minute: Int) -> Date {
        let start = calendar.startOfDay(for: now)
        let day = calendar.date(byAdding: .day, value: daysFromNow, to: start) ?? start
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
    /// Regression: bests must compare in kilograms — 100 kg beats 200 lb
    /// (90.7 kg) even though 200 > 100 numerically.
    func testLiftBestsNormalizeUnitsWhenComparing() {
        let exercise = Exercise(
            name: "Bench",
            category: .chest,
            metrics: .weightAndRepsRequired,
            defaultRestSeconds: 90
        )
        let poundsSet = SetEntry(
            exercise: exercise,
            performedAt: date(daysFromNow: 0, hour: 9, minute: 0),
            weight: 200,
            weightUnit: .lb,
            reps: 5,
            restAfterSeconds: 90
        )
        let kilogramsSet = SetEntry(
            exercise: exercise,
            performedAt: date(daysFromNow: 0, hour: 10, minute: 0),
            weight: 100,
            weightUnit: .kg,
            reps: 3,
            restAfterSeconds: 90
        )

        let bests = ExerciseProgressBuilder.buildLiftBests(
            entries: [poundsSet, kilogramsSet],
            exercise: exercise,
            range: .all
        )

        XCTAssertEqual(bests?.heaviestEntry?.weight, 100)
        XCTAssertEqual(bests?.heaviestEntry?.weightUnit, .kg)
    }

}
