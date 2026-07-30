import Foundation
@testable import marble

/// One input/expected-output pair for the workout-text parsing evaluation corpus.
///
/// The corpus exists to pin the boundary between the two parsers:
///   • `.notation` cases are documented gym shorthand that the deterministic
///     `HandwrittenWorkoutParser` MUST parse exactly — they run in CI on every build.
///   • `.prose` cases are natural-language descriptions the deterministic parser
///     cannot handle; only the on-device model (`FoundationModelsWorkoutScanParser`)
///     can be expected to structure them. Their expectations define what the model
///     SHOULD produce, and they are scored in the opt-in live-model eval.
nonisolated struct WorkoutParseEvalCase: Sendable {
    enum Tier: Sendable {
        /// The deterministic parser must nail this exactly.
        case notation
        /// Only the on-device model can be expected to parse this.
        case prose
    }

    var name: String
    var input: String
    var tier: Tier
    var expected: ExpectedWorkout
}

/// The expected structure for a corpus case. All optionals mean "don't check" so
/// each case only asserts what it actually pins down (relative dates, for example,
/// are best-effort and left unchecked).
nonisolated struct ExpectedWorkout: Sendable {
    var title: String?
    var month: Int?
    var day: Int?
    var year: Int?
    var exercises: [ExpectedExercise]

    init(
        title: String? = nil,
        month: Int? = nil,
        day: Int? = nil,
        year: Int? = nil,
        exercises: [ExpectedExercise]
    ) {
        self.title = title
        self.month = month
        self.day = day
        self.year = year
        self.exercises = exercises
    }
}

/// Per-exercise expectations. Optional per-set values are checked against the FIRST
/// set only — the corpus pins the shape of the parse, not every repeated set, and
/// most notations produce identical sets anyway.
nonisolated struct ExpectedExercise: Sendable {
    var name: String
    var setCount: Int
    var reps: Int?
    var weight: Double?
    var restSeconds: Int?
    var durationSeconds: Int?
    var distance: Double?
    /// Unit `distance` is expressed in. Comparison happens in meters, so a parser
    /// that reports "5 kilometers" as 5000 m is a pass, not a failure.
    var distanceUnit: DistanceUnit

    init(
        name: String,
        setCount: Int,
        reps: Int? = nil,
        weight: Double? = nil,
        restSeconds: Int? = nil,
        durationSeconds: Int? = nil,
        distance: Double? = nil,
        distanceUnit: DistanceUnit = .kilometers
    ) {
        self.name = name
        self.setCount = setCount
        self.reps = reps
        self.weight = weight
        self.restSeconds = restSeconds
        self.durationSeconds = durationSeconds
        self.distance = distance
        self.distanceUnit = distanceUnit
    }
}

extension WorkoutParseEvalCase {

    /// Scores a parsed draft against an expectation, returning human-readable
    /// failure strings so a failing eval reads like a diff, not a boolean.
    /// The judgment the app itself makes: two names are the "same exercise" when
    /// the matcher would resolve one onto the other at any confidence.
    private static func namesResolveTogether(_ actual: String, _ expected: String) -> Bool {
        let matcher = ExerciseMatcher(candidates: [
            ExerciseMatcher.Candidate(id: UUID(), name: expected)
        ])
        return matcher.bestMatch(for: actual) != nil
    }

    static func matches(_ draft: ParsedWorkoutDraft, _ expected: ExpectedWorkout) -> (pass: Bool, failures: [String]) {
        var failures: [String] = []

        if let expectedTitle = expected.title {
            let actual = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if actual.lowercased() != expectedTitle.lowercased() {
                failures.append("title: expected \"\(expectedTitle)\", got \"\(actual)\"")
            }
        }

        // Date is compared as calendar components in the same fixed UTC calendar the
        // parser uses, so the noon-UTC anchoring detail doesn't leak into cases.
        if expected.month != nil || expected.day != nil || expected.year != nil {
            if let performedAt = draft.performedAt {
                let components = Self.utcCalendar.dateComponents([.year, .month, .day], from: performedAt)
                if let month = expected.month, components.month != month {
                    failures.append("date: expected month \(month), got \(components.month.map(String.init) ?? "nil")")
                }
                if let day = expected.day, components.day != day {
                    failures.append("date: expected day \(day), got \(components.day.map(String.init) ?? "nil")")
                }
                if let year = expected.year, components.year != year {
                    failures.append("date: expected year \(year), got \(components.year.map(String.init) ?? "nil")")
                }
            } else {
                failures.append("date: expected a performedAt date, got nil")
            }
        }

        if draft.exercises.count != expected.exercises.count {
            failures.append("expected \(expected.exercises.count) exercises, got \(draft.exercises.count) (\(draft.exercises.map(\.name).joined(separator: ", ")))")
            // Counts differ, so positional per-exercise checks would only add noise.
            return (false, failures)
        }

        for (index, expectedExercise) in expected.exercises.enumerated() {
            let actual = draft.exercises[index]
            let actualName = actual.trimmedName
            // Names pass when they'd resolve to the same library exercise — that is
            // what the app does with parsed names, so "Bench Press" vs "bench" or
            // "Pull-ups" vs "Pull Ups" are correct parses, not failures.
            if !namesResolveTogether(actualName, expectedExercise.name) {
                failures.append("exercise \(index): expected name \"\(expectedExercise.name)\", got \"\(actualName)\"")
            }
            if actual.sets.count != expectedExercise.setCount {
                failures.append("exercise \(index): expected \(expectedExercise.setCount) sets, got \(actual.sets.count)")
            }
            guard let firstSet = actual.sets.first else {
                if expectedExercise.reps != nil || expectedExercise.weight != nil || expectedExercise.restSeconds != nil
                    || expectedExercise.durationSeconds != nil || expectedExercise.distance != nil {
                    failures.append("exercise \(index): has no sets to check per-set expectations against")
                }
                continue
            }
            if let reps = expectedExercise.reps, firstSet.reps != reps {
                failures.append("exercise \(index) set 0: expected \(reps) reps, got \(firstSet.reps.map(String.init) ?? "nil")")
            }
            if let weight = expectedExercise.weight {
                if let actualWeight = firstSet.weight {
                    if abs(actualWeight - weight) > 0.001 {
                        failures.append("exercise \(index) set 0: expected weight \(weight), got \(actualWeight)")
                    }
                } else {
                    failures.append("exercise \(index) set 0: expected weight \(weight), got nil")
                }
            }
            if let rest = expectedExercise.restSeconds, firstSet.restSeconds != rest {
                failures.append("exercise \(index) set 0: expected rest \(rest)s, got \(firstSet.restSeconds.map(String.init) ?? "nil")")
            }
            if let duration = expectedExercise.durationSeconds, firstSet.durationSeconds != duration {
                failures.append("exercise \(index) set 0: expected duration \(duration)s, got \(firstSet.durationSeconds.map(String.init) ?? "nil")")
            }
            if let distance = expectedExercise.distance {
                let expectedMeters = expectedExercise.distanceUnit.meters(from: distance)
                if let actualDistance = firstSet.distance {
                    let actualMeters = firstSet.distanceUnit.meters(from: actualDistance)
                    if abs(actualMeters - expectedMeters) > 0.5 {
                        failures.append("exercise \(index) set 0: expected distance \(expectedMeters)m, got \(actualMeters)m")
                    }
                } else {
                    failures.append("exercise \(index) set 0: expected distance \(distance), got nil")
                }
            }
        }

        return (failures.isEmpty, failures)
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()
}

extension WorkoutParseEvalCase {

    static let all: [WorkoutParseEvalCase] = notationCases + proseCases

    // MARK: - Notation tier

    /// Straight from the deterministic parser's documented notations. These must
    /// parse exactly on every build — no model involved.
    static let notationCases: [WorkoutParseEvalCase] = [
        WorkoutParseEvalCase(
            name: "sets x reps",
            input: "Squat 5x5",
            tier: .notation,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Squat", setCount: 5, reps: 5)
            ])
        ),
        WorkoutParseEvalCase(
            name: "sets x reps @ weight with unit",
            input: "Bench Press 3x5 @ 135 lb",
            tier: .notation,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Bench Press", setCount: 3, reps: 5, weight: 135)
            ])
        ),
        WorkoutParseEvalCase(
            name: "trailing bare weight",
            input: "Squat 5x5 225",
            tier: .notation,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Squat", setCount: 5, reps: 5, weight: 225)
            ])
        ),
        WorkoutParseEvalCase(
            name: "embedded weight SxRxW",
            input: "Squat 5x5x225",
            tier: .notation,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Squat", setCount: 5, reps: 5, weight: 225)
            ])
        ),
        WorkoutParseEvalCase(
            name: "single weight x reps set",
            input: "Deadlift 315x5",
            tier: .notation,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Deadlift", setCount: 1, reps: 5, weight: 315)
            ])
        ),
        WorkoutParseEvalCase(
            name: "weight x reps pair list",
            input: "Bench 135x5 155x3 175x1",
            tier: .notation,
            expected: ExpectedWorkout(exercises: [
                // Only the first set is checked per-set; the set count pins the pairs.
                ExpectedExercise(name: "Bench", setCount: 3, reps: 5, weight: 135)
            ])
        ),
        WorkoutParseEvalCase(
            name: "timed sets in seconds",
            input: "Plank 3x30s",
            tier: .notation,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Plank", setCount: 3, durationSeconds: 30)
            ])
        ),
        WorkoutParseEvalCase(
            name: "cardio distance plus time",
            input: "Run 5k 25:00",
            tier: .notation,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Run", setCount: 1, durationSeconds: 25 * 60, distance: 5)
            ])
        ),
        WorkoutParseEvalCase(
            name: "date header with title and exercises",
            // No year written, so the parser adopts the reference year (2025 for
            // MarbleTestCase.fixedNow).
            input: "7/22 Push Day\nOHP 5x5 @ 95\nDips 3x12",
            tier: .notation,
            expected: ExpectedWorkout(
                title: "Push Day",
                month: 7,
                day: 22,
                year: 2025,
                exercises: [
                    ExpectedExercise(name: "OHP", setCount: 5, reps: 5, weight: 95),
                    ExpectedExercise(name: "Dips", setCount: 3, reps: 12)
                ]
            )
        ),
        WorkoutParseEvalCase(
            name: "inline rest with unit",
            input: "Bench 3x8 rest 90s",
            tier: .notation,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Bench", setCount: 3, reps: 8, restSeconds: 90)
            ])
        ),
        WorkoutParseEvalCase(
            name: "rest-only continuation line",
            input: "Squat 5x5\nrest 2min",
            tier: .notation,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Squat", setCount: 5, reps: 5, restSeconds: 120)
            ])
        ),
        WorkoutParseEvalCase(
            name: "at-weight with colon rest",
            input: "KB swings 3x20 @ 53 rest 1:30",
            tier: .notation,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "KB swings", setCount: 3, reps: 20, weight: 53, restSeconds: 90)
            ])
        )
    ]

    // MARK: - Prose tier

    /// Natural-language descriptions the deterministic parser cannot structure. The
    /// expectations here define the target output for the on-device model; they are
    /// scored only in the opt-in live eval (FoundationModelsLiveEvalTests).
    static let proseCases: [WorkoutParseEvalCase] = [
        WorkoutParseEvalCase(
            name: "prose two exercises with rest",
            input: "I did three sets of eight on bench at 185, then incline dumbbell press for 3 sets of 10 at 60 pounds, resting about 90 seconds between sets",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Bench", setCount: 3, reps: 8, weight: 185),
                ExpectedExercise(name: "Incline Dumbbell Press", setCount: 3, reps: 10, weight: 60)
            ])
        ),
        WorkoutParseEvalCase(
            name: "prose circuit rounds",
            input: "three rounds of 10 pushups, 15 air squats, and 20 situps",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Pushups", setCount: 3, reps: 10),
                ExpectedExercise(name: "Air Squats", setCount: 3, reps: 15),
                ExpectedExercise(name: "Situps", setCount: 3, reps: 20)
            ])
        ),
        WorkoutParseEvalCase(
            name: "prose vague second exercise",
            input: "Did 4 sets of 12 lat pulldowns at 120 then some curls, 3 sets of 10 with 25 pound dumbbells",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Lat Pulldowns", setCount: 4, reps: 12, weight: 120),
                ExpectedExercise(name: "Curls", setCount: 3, reps: 10, weight: 25)
            ])
        ),
        WorkoutParseEvalCase(
            name: "prose cardio sentence",
            input: "ran 5 kilometers in 25 minutes",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Run", setCount: 1, durationSeconds: 25 * 60, distance: 5)
            ])
        ),
        WorkoutParseEvalCase(
            name: "prose worked up to a double",
            input: "worked up to 225 on bench for a double",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Bench", setCount: 1, reps: 2, weight: 225)
            ])
        ),
        WorkoutParseEvalCase(
            name: "prose leg day with spelled numbers",
            input: "leg day: squats five sets of five at 225, leg press three sets of fifteen",
            tier: .prose,
            expected: ExpectedWorkout(
                title: "Leg Day",
                exercises: [
                    ExpectedExercise(name: "Squats", setCount: 5, reps: 5, weight: 225),
                    ExpectedExercise(name: "Leg Press", setCount: 3, reps: 15)
                ]
            )
        ),
        WorkoutParseEvalCase(
            name: "prose timed plank circuit",
            input: "20 minute plank circuit, 3 planks of 45 seconds each",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Plank", setCount: 3, durationSeconds: 45)
            ])
        ),
        WorkoutParseEvalCase(
            name: "prose bench with rest",
            input: "bench pressed 185 for 3 sets of 8 with 90 seconds rest",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Bench Press", setCount: 3, reps: 8, weight: 185, restSeconds: 90)
            ])
        ),
        WorkoutParseEvalCase(
            name: "prose bodyweight pull ups",
            input: "did pull ups, 4 sets of 10",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Pull Ups", setCount: 4, reps: 10)
            ])
        ),
        WorkoutParseEvalCase(
            name: "prose relative date deadlifts",
            // Relative dates ("yesterday") are best-effort, so the date is
            // deliberately unchecked — only the structured exercise matters.
            input: "yesterday's workout was deadlifts 5 sets of 3 at 315",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Deadlifts", setCount: 5, reps: 3, weight: 315)
            ])
        ),
        WorkoutParseEvalCase(
            name: "prose five by five",
            input: "overhead press 5 by 5 at 95 pounds",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Overhead Press", setCount: 5, reps: 5, weight: 95)
            ])
        ),
        WorkoutParseEvalCase(
            name: "prose notation-first goblet squats",
            input: "3x10 goblet squats with a 50 pound dumbbell",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Goblet Squats", setCount: 3, reps: 10, weight: 50)
            ])
        )
    ]
}
