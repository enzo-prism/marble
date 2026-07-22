import XCTest
@testable import marble

final class QuickLogBestCueTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 4_000_000_000)

    func testRequiredWeightUsesUnitNormalizedHeaviestEntry() {
        let exercise = Exercise(
            name: "Bench Press",
            category: .chest,
            metrics: .weightAndRepsRequired,
            defaultRestSeconds: 90
        )
        let kilograms = entry(exercise, secondsAgo: 60, weight: 100, unit: .kg, reps: 3)
        let latest = entry(exercise, secondsAgo: 0, weight: 220, unit: .lb, reps: 5)

        let cue = QuickLogBestCueResolver.resolve(latest: latest, entries: [latest, kilograms])

        XCTAssertEqual(cue?.text, "Best weight · 100 kg")
        XCTAssertEqual(cue?.accessibilityLabel, "Best weight, 100 kg")
    }

    func testDumbbellPairDisplaysThePerHandWeight() {
        let exercise = Exercise(
            name: "Dumbbell Shoulder Press",
            category: .shoulders,
            resistanceTrackingStyle: .singleDumbbellPair,
            metrics: .weightAndRepsRequired,
            defaultRestSeconds: 90
        )
        let latest = entry(exercise, secondsAgo: 0, weight: 100, unit: .lb, reps: 8)

        let cue = QuickLogBestCueResolver.resolve(latest: latest, entries: [latest])

        XCTAssertEqual(cue?.text, "Best weight · 50 lb each")
    }

    func testOptionalAddedWeightStillUsesMostRepsForBodyweightExercise() {
        let exercise = Exercise(
            name: "Pull Ups",
            category: .back,
            metrics: ExerciseMetricsProfile(
                weight: .optional,
                reps: .required,
                distance: .none,
                durationSeconds: .none
            ),
            defaultRestSeconds: 90
        )
        let loaded = entry(exercise, secondsAgo: 60, weight: 45, unit: .lb, reps: 8)
        let latest = entry(exercise, secondsAgo: 0, weight: nil, unit: .lb, reps: 14)

        let cue = QuickLogBestCueResolver.resolve(latest: latest, entries: [loaded, latest])

        XCTAssertEqual(cue?.text, "Most reps · 14")
        XCTAssertEqual(cue?.accessibilityLabel, "Most reps, 14 reps")
    }

    func testRunBestTimeComparesOnlyTheLatestDistanceAcrossUnits() {
        let run = Exercise(
            name: "Run",
            category: .run,
            metrics: .distanceAndDurationRequired,
            defaultRestSeconds: 0
        )
        let priorFiveK = entry(
            run,
            secondsAgo: 120,
            distance: 5000,
            distanceUnit: .meters,
            duration: 1_500
        )
        let shortSprint = entry(
            run,
            secondsAgo: 60,
            distance: 100,
            distanceUnit: .meters,
            duration: 12
        )
        let latest = entry(
            run,
            secondsAgo: 0,
            distance: 5,
            distanceUnit: .kilometers,
            duration: 1_800
        )

        let cue = QuickLogBestCueResolver.resolve(
            latest: latest,
            entries: [shortSprint, latest, priorFiveK]
        )

        XCTAssertEqual(cue?.text, "Best time · 25:00 for 5 km")
        XCTAssertEqual(cue?.accessibilityLabel, "Best time for 5 km, 25 minutes")
    }

    func testRunBestTimeAllowsSmallGPSDistanceDrift() {
        let run = Exercise(
            name: "Morning Run",
            category: .run,
            metrics: .distanceAndDurationRequired,
            defaultRestSeconds: 0
        )
        let gpsRun = entry(
            run,
            secondsAgo: 60,
            distance: 5_020,
            distanceUnit: .meters,
            duration: 1_440
        )
        let latest = entry(
            run,
            secondsAgo: 0,
            distance: 5,
            distanceUnit: .kilometers,
            duration: 1_500
        )

        let cue = QuickLogBestCueResolver.resolve(latest: latest, entries: [latest, gpsRun])

        XCTAssertEqual(cue?.text, "Best time · 24:00 for 5 km")
    }

    func testRunBestTimeRejectsMateriallyDifferentDistance() {
        let run = Exercise(
            name: "Morning Run",
            category: .run,
            metrics: .distanceAndDurationRequired,
            defaultRestSeconds: 0
        )
        let differentRoute = entry(
            run,
            secondsAgo: 60,
            distance: 5_100,
            distanceUnit: .meters,
            duration: 1_200
        )
        let latest = entry(
            run,
            secondsAgo: 0,
            distance: 5,
            distanceUnit: .kilometers,
            duration: 1_500
        )

        let cue = QuickLogBestCueResolver.resolve(latest: latest, entries: [differentRoute, latest])

        XCTAssertEqual(cue?.text, "Best time · 25:00 for 5 km")
    }

    func testEntriesForAnotherExerciseCannotSetTheBest() {
        let press = Exercise(
            name: "Shoulder Press",
            category: .shoulders,
            metrics: .weightAndRepsRequired,
            defaultRestSeconds: 90
        )
        let squat = Exercise(
            name: "Squat",
            category: .legs,
            metrics: .weightAndRepsRequired,
            defaultRestSeconds: 120
        )
        let latest = entry(press, secondsAgo: 0, weight: 115, unit: .lb, reps: 5)
        let unrelated = entry(squat, secondsAgo: 60, weight: 500, unit: .lb, reps: 1)

        let cue = QuickLogBestCueResolver.resolve(latest: latest, entries: [unrelated, latest])

        XCTAssertEqual(cue?.text, "Best weight · 115 lb")
    }

    func testInvalidAndDurationOnlyHistoryDoNotClaimABest() {
        let timed = Exercise(
            name: "Plank",
            category: .core,
            metrics: .durationOnlyRequired,
            defaultRestSeconds: 60
        )
        let latest = entry(timed, secondsAgo: 0, duration: 120)

        XCTAssertNil(QuickLogBestCueResolver.resolve(latest: latest, entries: [latest]))

        let bodyweight = Exercise(
            name: "Push Ups",
            category: .chest,
            metrics: .repsOnlyRequired,
            defaultRestSeconds: 60
        )
        let invalid = entry(bodyweight, secondsAgo: 0, reps: 0)
        XCTAssertNil(QuickLogBestCueResolver.resolve(latest: invalid, entries: [invalid]))
    }

    private func entry(
        _ exercise: Exercise,
        secondsAgo: TimeInterval,
        weight: Double? = nil,
        unit: WeightUnit = .lb,
        reps: Int? = nil,
        distance: Double? = nil,
        distanceUnit: DistanceUnit = .meters,
        duration: Int? = nil
    ) -> SetEntry {
        let date = now.addingTimeInterval(-secondsAgo)
        return SetEntry(
            exercise: exercise,
            performedAt: date,
            weight: weight,
            weightUnit: unit,
            reps: reps,
            distance: distance,
            distanceUnit: distanceUnit,
            durationSeconds: duration,
            restAfterSeconds: exercise.defaultRestSeconds,
            createdAt: date,
            updatedAt: date
        )
    }
}
