import Foundation
@testable import marble

// =============================================================================
// HARD CORPUS — realistic user-typed / dictated workout logs for the Apple
// Intelligence parse path (FoundationModelsWorkoutScanParser + arbiter).
//
// Reference: MarbleTestCase.fixedNow = 2025-01-15T12:00:00Z (a WEDNESDAY), test
// time zone forced to GMT. Default weight unit is .lb unless the case sets
// `defaultWeightUnit: .kg` (section L). Resolved relative dates:
//   yesterday → 2025-01-14, "Mon" → 01-13, "Saturday" → 01-11, "two days ago" → 01-13,
//   "1/10" → 2025-01-10, "Jan 12" → 2025-01-12 (year-less dates roll back, never future).
//
// COVERAGE (71 cases)
//   A. Voice dictation (no punctuation, number words, "um/like", "and then")  9
//   B. Notes-app shorthand (bullets, ✅, arrows, OHP/RDL/DB/BB/KB/BW,
//      AMRAP, EMOM, PR, RPE 8 / @8, per-line rest)                            9
//   C. Units: explicit kg, explicit lb, mixed per exercise, decimal kg         4
//   D. Per-set variation (worked-up ramps, rep ladders, drop sets, pyramids)   5
//   E. Bodyweight + weighted bodyweight ("+25", "w/ 45 lb plate")              4
//   F. Timed / cardio (5k in 24:30, 2000m 7:45, 20 min bike, 3 x 1 min,
//      h:mm:ss, each-side holds)                                               8
//   G. Supersets / circuits / "each side"                                      4
//   H. Warmups to ignore                                                       1
//   I. Dated headers + titles (Mon, Saturday, 1/10, Jan 12, "two days ago")    5
//   J. Typos                                                                   3
//   K. Non-English (ES, DE) — names chosen as loanwords so they're unambiguous 2
//   L. User default = kg, unit-less weights (+ explicit "lb"/"pounds" overrides) 8
//   M. Real inputs the deterministic parser mangles                            9
//
// Every case is .prose (C1/C4 were demoted from .notation: unverified against
// HandwrittenWorkoutParser). Every expected weight carries weightUnit: .lb unless kg
// is written or the case's default is kg. perSetReps/perSetWeights are pinned on
// every case whose sets differ (B8, D1-D5, E4 reps, L6, M2, M3).
//
// Judgment calls a reviewer may want to revisit:
//   • One movement = ONE entry (parser instructions, FoundationModelsWorkoutParser
//     .swift:118-119): top set + back-offs of the same lift merge (B8, M2, M3).
//   • "each side"/"each leg" never changes setCount (same file :142-143).
//   • M1 "Bench 225x5x3" reads weight×reps×sets (3 sets of 5 @ 225): the leading
//     number can only be the load, and this is the usual order when it leads. It is
//     the least certain expectation in the file.
//   • M3 "Squat 100kg 5x5 then 3x10 at 80": the unit-less 80 inherits kg from the
//     same exercise's explicit "100kg" (weightUnit is checked on every set).
//
// MATCHER LIMITATIONS (Tests/Unit/WorkoutParseEvalCorpus.swift, pre-extension line
// numbers from the original read; unit + per-set arrays have since been added)
//  1. [RESOLVED by coordinator] weight unit was never compared; per-set arrays
//     weren't checkable. Remaining gap: `weightUnit` is only checked on sets that
//     carry a weight, so a unit is vacuously correct when weight is dropped.
//  2. reps/weight/rest/duration/distance scalars still check set 0 only.
//  3. setCount is non-optional — it can never be left unchecked.
//  4. nil means "don't check" — no way to assert ABSENCE (bodyweight weight nil,
//     "@8" not becoming a weight, no date, no invented rest).
//  5. Title is exact, case-insensitive (:104-108). "Push A ✅" ≠ "Push A". Can't
//     assert "no title" (default "Scanned workout", WorkoutScanDraft.swift:32).
//  6. Names go through ExerciseMatcher. False NEGATIVES: tokens < 4 chars must match
//     exactly (ExerciseMatcher.swift:138) so "Rowing" ≠ "Row", "Running" ≠ "Run";
//     joined vs split compounds fail the 0.75 token threshold (:103): "Pullups" ≠
//     "Pull Ups", "Pushups" ≠ "Push Ups", "Lat Pull Down" ≠ "Lat Pulldown"; "Biking"
//     ≠ "Bike"; no cross-language aliases. False POSITIVES from the 0.55 threshold
//     (:99): "Bench Press" passes for "Incline Bench Press", "Plank" for "Side Plank".
//  7. Exercise-count mismatch returns early; comparison is positional.
//  8. Tolerances: weight ±0.001, distance ±0.5 m, rest/duration exact Int.
//  9. Not checked: difficulty/RPE (WorkoutScanDraft.swift:125), set notes (:128),
//     workout-level durationSeconds (:20), endedAt.
// 10. Live test iterates only `.all` (FoundationModelsLiveEvalTests.swift:36) with one
//     0.8 gate (:21) — give `hard` its own test/threshold; it must also pass each
//     case's `defaultWeightUnit` into FoundationModelsWorkoutScanParser(init:).
// 11. The eval scores the arbiter's pick (FoundationModelsWorkoutParser.swift:102-106),
//     not the model alone.
// 12. The generate path drops weight when the model labels the unit "bodyweight"
//     (FoundationModelsWorkoutParser.swift:346-347) — E1, E2, L4 probe this. It also
//     maps weightUnit "unknown" to .lb (:345), ignoring defaultWeightUnit — L-cases
//     with unit-less weights probe that.
// =============================================================================

extension WorkoutParseEvalCase {

    static let hard: [WorkoutParseEvalCase] = [

        // MARK: - A. Voice dictation

        WorkoutParseEvalCase(
            name: "A1 dictation: spoken weights and 'the sixties'",
            // "one eighty five" = 185. "with the sixties" is gym slang for the 60 lb
            // dumbbells. No punctuation, filler words.
            input: "um so i did bench press three sets of eight at one eighty five and then like incline dumbbell press three sets of ten with the sixties",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Bench Press", setCount: 3, reps: 8, weight: 185, weightUnit: .lb),
                ExpectedExercise(name: "Incline Dumbbell Press", setCount: 3, reps: 10, weight: 60, weightUnit: .lb)
            ])
        ),
        WorkoutParseEvalCase(
            name: "A2 dictation: squats with spoken rest in minutes",
            // "two twenty five" = 225; "three minutes" rest → 180 s.
            input: "squats five sets of five at two twenty five resting three minutes between sets",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Squat", setCount: 5, reps: 5, weight: 225, weightUnit: .lb, restSeconds: 180)
            ])
        ),
        WorkoutParseEvalCase(
            name: "A3 dictation: run in miles then plank",
            // 3 miles (compared in meters), 27 min = 1620 s; plank 2 min = 120 s.
            input: "went for a run three miles in twenty seven minutes and then did a plank for two minutes",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Run", setCount: 1, durationSeconds: 1620, distance: 3, distanceUnit: .miles),
                ExpectedExercise(name: "Plank", setCount: 1, durationSeconds: 120)
            ])
        ),
        WorkoutParseEvalCase(
            name: "A4 dictation: heavy filler 'like' 'um' 'uh'",
            // "at like three fifteen" = 315; filler must not leak into names or numbers.
            input: "okay so like deadlifts um four sets of three at like three fifteen and uh then barbell rows four sets of eight at one thirty five",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Deadlift", setCount: 4, reps: 3, weight: 315, weightUnit: .lb),
                ExpectedExercise(name: "Barbell Row", setCount: 4, reps: 8, weight: 135, weightUnit: .lb)
            ])
        ),
        WorkoutParseEvalCase(
            name: "A5 dictation: kilos spoken, each leg",
            // "eighty kilos" → 80 (unit not checked, see limitation 1). "each leg" does not
            // change setCount or reps (product rule, parser instructions :142-143).
            input: "front squats three sets of six at eighty kilos then walking lunges three sets of twelve each leg",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Front Squat", setCount: 3, reps: 6, weight: 80, weightUnit: .kg),
                ExpectedExercise(name: "Walking Lunges", setCount: 3, reps: 12)
            ])
        ),
        WorkoutParseEvalCase(
            name: "A6 dictation: bodyweight pull ups and max-effort chin ups",
            // "as many as i could" = AMRAP: 3 sets, reps genuinely unknown → unchecked.
            // Name caveat: "Pullups"/"Chinups" (joined) fail the matcher (limitation 6).
            input: "pull ups four sets of eight then chin ups three sets as many as i could",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Pull Ups", setCount: 4, reps: 8),
                ExpectedExercise(name: "Chin Ups", setCount: 3)
            ])
        ),
        WorkoutParseEvalCase(
            name: "A7 dictation: yesterday with spoken load",
            // "yesterday" → 2025-01-14 via resolveDateText. "three sixty" = 360.
            input: "yesterday i did leg press four sets of twelve at three sixty",
            tier: .prose,
            expected: ExpectedWorkout(
                month: 1,
                day: 14,
                year: 2025,
                exercises: [
                    ExpectedExercise(name: "Leg Press", setCount: 4, reps: 12, weight: 360, weightUnit: .lb)
                ]
            )
        ),
        WorkoutParseEvalCase(
            name: "A8 long multi-exercise paragraph with distractor numbers",
            // "around 6" is a clock time, never a weight. "each leg" leaves reps at 8.
            // "10 minutes on the bike" = one 600 s effort.
            input: "Got to the gym around 6, started with squats 4 sets of 6 at 245 which felt heavy, then romanian deadlifts 3 sets of 10 at 185, bulgarian split squats 3 sets of 8 each leg holding 40 lb dumbbells, leg extensions 3 sets of 15 at 110, and finished with 10 minutes on the bike",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Squat", setCount: 4, reps: 6, weight: 245, weightUnit: .lb),
                ExpectedExercise(name: "Romanian Deadlift", setCount: 3, reps: 10, weight: 185, weightUnit: .lb),
                ExpectedExercise(name: "Bulgarian Split Squat", setCount: 3, reps: 8, weight: 40, weightUnit: .lb),
                ExpectedExercise(name: "Leg Extension", setCount: 3, reps: 15, weight: 110, weightUnit: .lb),
                ExpectedExercise(name: "Bike", setCount: 1, durationSeconds: 600)
            ])
        ),
        WorkoutParseEvalCase(
            name: "A9 dictation: kettlebell circuit rounds with spoken pounds",
            // "three rounds of" multiplies every movement in the round (setCount 3).
            input: "three rounds of twenty kettlebell swings at fifty three pounds ten burpees and fifteen box jumps",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Kettlebell Swings", setCount: 3, reps: 20, weight: 53, weightUnit: .lb),
                ExpectedExercise(name: "Burpees", setCount: 3, reps: 10),
                ExpectedExercise(name: "Box Jumps", setCount: 3, reps: 15)
            ])
        ),

        // MARK: - B. Notes-app shorthand

        WorkoutParseEvalCase(
            name: "B1 bullets, checkmark title, OHP / DB / tri",
            // "70s" = 70 lb dumbbells (not seconds: no timed movement here). Title left
            // unchecked because "Push A ✅" vs "Push A" is an exact-string coin flip.
            input: """
            Push A ✅
            • OHP 4x6 @ 115
            • DB bench 3x10 @ 70s
            • tri pushdown 3x15
            """,
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Overhead Press", setCount: 4, reps: 6, weight: 115, weightUnit: .lb),
                ExpectedExercise(name: "Dumbbell Bench Press", setCount: 3, reps: 10, weight: 70, weightUnit: .lb),
                ExpectedExercise(name: "Triceps Pushdown", setCount: 3, reps: 15)
            ])
        ),
        WorkoutParseEvalCase(
            name: "B2 arrows between name and spec",
            input: """
            Squat → 3x5 @ 275
            RDL → 3x8 @ 225
            Leg curl → 3x12
            """,
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Squat", setCount: 3, reps: 5, weight: 275, weightUnit: .lb),
                ExpectedExercise(name: "Romanian Deadlift", setCount: 3, reps: 8, weight: 225, weightUnit: .lb),
                ExpectedExercise(name: "Leg Curl", setCount: 3, reps: 12)
            ])
        ),
        WorkoutParseEvalCase(
            name: "B3 RPE 8 and '@8' are not loads",
            // "@ 185 @8": the first @ is the load, "@8" is RPE shorthand. Paused bench is
            // a distinct variation, so two entries.
            input: """
            Bench 3x5 @ 205 RPE 8
            Paused bench 2x3 @ 185 @8
            """,
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Bench", setCount: 3, reps: 5, weight: 205, weightUnit: .lb),
                ExpectedExercise(name: "Paused Bench", setCount: 2, reps: 3, weight: 185, weightUnit: .lb)
            ])
        ),
        WorkoutParseEvalCase(
            name: "B4 EMOM with load and em dash",
            // EMOM 10 min → one set per minute: 10 sets of 3.
            input: "EMOM 10 min — 3 hang power cleans @ 155",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Hang Power Clean", setCount: 10, reps: 3, weight: 155, weightUnit: .lb)
            ])
        ),
        WorkoutParseEvalCase(
            name: "B5 AMRAP with completed-rounds score",
            // 8 full rounds completed → 8 sets of each movement. "15 min" is the cap,
            // not a per-set duration, so duration is unchecked.
            input: "AMRAP 15 min: 5 pull ups, 10 push ups, 15 air squats — got 8 rounds",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Pull Ups", setCount: 8, reps: 5),
                ExpectedExercise(name: "Push Ups", setCount: 8, reps: 10),
                ExpectedExercise(name: "Air Squats", setCount: 8, reps: 15)
            ])
        ),
        WorkoutParseEvalCase(
            name: "B6 BB / KB / BW prefixes",
            // BW dips have no load; weight left unchecked (can't assert nil, limitation 4).
            input: """
            BB row 4x10 @ 155
            KB goblet squat 3x12 @ 53
            BW dips 3x15
            """,
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Barbell Row", setCount: 4, reps: 10, weight: 155, weightUnit: .lb),
                ExpectedExercise(name: "Kettlebell Goblet Squat", setCount: 3, reps: 12, weight: 53, weightUnit: .lb),
                ExpectedExercise(name: "Dips", setCount: 3, reps: 15)
            ])
        ),
        WorkoutParseEvalCase(
            name: "B7 trailing emoji noise",
            input: """
            🏋️ deadlift 5x3 @ 365 🔥
            💪 curls 3x12 @ 30 😅
            """,
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Deadlift", setCount: 5, reps: 3, weight: 365, weightUnit: .lb),
                ExpectedExercise(name: "Curls", setCount: 3, reps: 12, weight: 30, weightUnit: .lb)
            ])
        ),
        WorkoutParseEvalCase(
            name: "B8 PR single then back-offs on the same lift",
            // One movement → ONE entry (parser instructions :118-119): 1 top set + 3
            // back-off sets = 4 sets; set 0 is the 315 single.
            input: "Squat PR!! 315x1 🎉 then backoffs 3x5 @ 255",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Squat", setCount: 4, reps: 1, weight: 315, weightUnit: .lb, perSetReps: [1, 5, 5, 5], perSetWeights: [315, 255, 255, 255])
            ])
        ),
        WorkoutParseEvalCase(
            name: "B9 dash bullets with per-exercise rest",
            // "incline DB" alone names Incline Dumbbell Press (matcher accepts either).
            input: """
            - incline DB 3x10 @ 55, 60s rest
            - cable fly 3x15, 45s rest
            """,
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Incline Dumbbell Press", setCount: 3, reps: 10, weight: 55, weightUnit: .lb, restSeconds: 60),
                ExpectedExercise(name: "Cable Fly", setCount: 3, reps: 15, restSeconds: 45)
            ])
        ),

        // MARK: - C. Units

        WorkoutParseEvalCase(
            name: "C1 explicit kg notation",
            // Plain notation, kept .prose: unverified against the deterministic parser.
            input: "Bench 4x6 @ 80kg\nSquat 5x5 @ 100 kg",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Bench", setCount: 4, reps: 6, weight: 80, weightUnit: .kg),
                ExpectedExercise(name: "Squat", setCount: 5, reps: 5, weight: 100, weightUnit: .kg)
            ])
        ),
        WorkoutParseEvalCase(
            name: "C2 mixed kg then lbs in one sentence",
            // Numbers as written: 140 (kg) and 80 (lb). A model that converts either
            // fails — correctly.
            input: "deadlift 3x5 at 140kg, then DB rows 3x10 with 80 lbs dumbbells",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Deadlift", setCount: 3, reps: 5, weight: 140, weightUnit: .kg),
                ExpectedExercise(name: "Dumbbell Row", setCount: 3, reps: 10, weight: 80, weightUnit: .lb)
            ])
        ),
        WorkoutParseEvalCase(
            name: "C3 kilos and pounds as words",
            input: "hip thrusts 4 sets of 10 at 100 kilos and calf raises 3 sets of 15 at 90 pounds",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Hip Thrusts", setCount: 4, reps: 10, weight: 100, weightUnit: .kg),
                ExpectedExercise(name: "Calf Raises", setCount: 3, reps: 15, weight: 90, weightUnit: .lb)
            ])
        ),
        WorkoutParseEvalCase(
            name: "C4 decimal kg load",
            // 42.5 must survive exactly (tolerance 0.001).
            input: "OHP 5x5 @ 42.5kg",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Overhead Press", setCount: 5, reps: 5, weight: 42.5, weightUnit: .kg)
            ])
        ),

        // MARK: - D. Per-set variation

        WorkoutParseEvalCase(
            name: "D1 worked up with parallel weight and rep lists",
            // Weights 135/185/225 pair with reps 5/5/3 → 3 sets, set 0 = 135x5.
            input: "worked up 135 185 225 for 5 5 3 on squat",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Squat", setCount: 3, reps: 5, weight: 135, weightUnit: .lb, perSetReps: [5, 5, 3], perSetWeights: [135, 185, 225])
            ])
        ),
        WorkoutParseEvalCase(
            name: "D2 rep ladder '3 sets 10 8 6 reps'",
            input: "3 sets 10 8 6 reps on lat pulldown at 120",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Lat Pulldown", setCount: 3, reps: 10, weight: 120, weightUnit: .lb, perSetReps: [10, 8, 6], perSetWeights: [120, 120, 120])
            ])
        ),
        WorkoutParseEvalCase(
            name: "D3 dictated pyramid",
            // "one thirty five for ten" = 135x10 etc. → 3 sets, set 0 = 135x10.
            input: "bench pyramid one thirty five for ten one fifty five for eight one seventy five for six",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Bench", setCount: 3, reps: 10, weight: 135, weightUnit: .lb, perSetReps: [10, 8, 6], perSetWeights: [135, 155, 175])
            ])
        ),
        WorkoutParseEvalCase(
            name: "D4 drop set listed as three pairs",
            // Each weight×reps pair is its own logged set.
            input: "cable curls drop set 50x10, 40x8, 30x8",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Cable Curl", setCount: 3, reps: 10, weight: 50, weightUnit: .lb, perSetReps: [10, 8, 8], perSetWeights: [50, 40, 30])
            ])
        ),
        WorkoutParseEvalCase(
            name: "D5 parallel rep and weight lists",
            // 4 sets; reps 12/10/8/8 pair positionally with 50/55/60/60 → set 0 = 50x12.
            input: "shoulder press 4 sets 12 10 8 8 at 50 55 60 60",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Shoulder Press", setCount: 4, reps: 12, weight: 50, weightUnit: .lb, perSetReps: [12, 10, 8, 8], perSetWeights: [50, 55, 60, 60])
            ])
        ),

        // MARK: - E. Bodyweight + weighted bodyweight

        WorkoutParseEvalCase(
            name: "E1 weighted pull ups '+25'",
            // "+25" is the added load → weight 25. Probes the bodyweight-unit drop
            // (limitation 12).
            input: "pull ups +25 3x6",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Pull Ups", setCount: 3, reps: 6, weight: 25, weightUnit: .lb)
            ])
        ),
        WorkoutParseEvalCase(
            name: "E2 weighted dips with a plate",
            input: "dips w/ 45 lb plate 3x8",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Dips", setCount: 3, reps: 8, weight: 45, weightUnit: .lb)
            ])
        ),
        WorkoutParseEvalCase(
            name: "E3 total reps restated as sets",
            // "100 total" is a sum, not a set; the sets are 5 x 20.
            input: "100 push ups total, 5 sets of 20",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Push Ups", setCount: 5, reps: 20)
            ])
        ),
        WorkoutParseEvalCase(
            name: "E4 to-failure sets with the actual counts listed",
            input: "chin ups 5 sets to failure: 12, 10, 8, 7, 6",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Chin Ups", setCount: 5, reps: 12, perSetReps: [12, 10, 8, 7, 6])
            ])
        ),

        // MARK: - F. Timed / cardio

        WorkoutParseEvalCase(
            name: "F1 ran 5k in mm:ss",
            // 24:30 = 1470 s; 5k = 5 km.
            input: "ran 5k in 24:30",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Run", setCount: 1, durationSeconds: 1470, distance: 5)
            ])
        ),
        WorkoutParseEvalCase(
            name: "F2 rowed 2000m with split time",
            // 7:45 = 465 s. Name caveat: "Rowing" fails vs "Row" (limitation 6).
            input: "rowed 2000m 7:45",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Row", setCount: 1, durationSeconds: 465, distance: 2000, distanceUnit: .meters)
            ])
        ),
        WorkoutParseEvalCase(
            name: "F3 20 min bike",
            input: "20 min bike",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Bike", setCount: 1, durationSeconds: 1200)
            ])
        ),
        WorkoutParseEvalCase(
            name: "F4 plank 3 x 1 min",
            // "1 min" is the per-set duration (60 s), never reps.
            input: "plank 3 x 1 min",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Plank", setCount: 3, durationSeconds: 60)
            ])
        ),
        WorkoutParseEvalCase(
            name: "F5 interval repeats with distance, time, and rest",
            // 4 sets of 400 m, each 1:30 (90 s), 90 s rest.
            input: "ran 4 x 400m in 1:30 each with 90 sec rest",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Run", setCount: 4, restSeconds: 90, durationSeconds: 90, distance: 400, distanceUnit: .meters)
            ])
        ),
        WorkoutParseEvalCase(
            name: "F6 jump rope rounds with rest",
            // 5 rounds × 3 min (180 s), 1 min rest (60 s).
            input: "jump rope 5 rounds of 3 min, 1 min rest",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Jump Rope", setCount: 5, restSeconds: 60, durationSeconds: 180)
            ])
        ),
        WorkoutParseEvalCase(
            name: "F7 h:mm:ss ride with decimal km",
            // 1:05:00 = 3900 s (hours:minutes:seconds, not mm:ss); 32.4 km.
            input: "bike 1:05:00 32.4 km",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Bike", setCount: 1, durationSeconds: 3900, distance: 32.4)
            ])
        ),
        WorkoutParseEvalCase(
            name: "F8 timed holds each side",
            // "each side" does not double the set count (parser instructions :142-143).
            input: "side plank 3x30s each side",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Side Plank", setCount: 3, durationSeconds: 30)
            ])
        ),

        // MARK: - G. Supersets / circuits / each side

        WorkoutParseEvalCase(
            name: "G1 A1/A2 B1/B2 superset labels",
            // Labels are grouping, not names or numbers; four movements in order.
            input: """
            A1 incline DB press 3x10 @ 50
            A2 chest supported row 3x12 @ 45
            B1 lateral raise 3x15 @ 20
            B2 face pull 3x15
            """,
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Incline Dumbbell Press", setCount: 3, reps: 10, weight: 50, weightUnit: .lb),
                ExpectedExercise(name: "Chest Supported Row", setCount: 3, reps: 12, weight: 45, weightUnit: .lb),
                ExpectedExercise(name: "Lateral Raise", setCount: 3, reps: 15, weight: 20, weightUnit: .lb),
                ExpectedExercise(name: "Face Pull", setCount: 3, reps: 15)
            ])
        ),
        WorkoutParseEvalCase(
            name: "G2 superset with respective loads",
            // "12 reps each" applies to both; "at 30 and 50" maps in order.
            input: "superset curls and pushdowns 3 rounds 12 reps each at 30 and 50",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Curls", setCount: 3, reps: 12, weight: 30, weightUnit: .lb),
                ExpectedExercise(name: "Pushdowns", setCount: 3, reps: 12, weight: 50, weightUnit: .lb)
            ])
        ),
        WorkoutParseEvalCase(
            name: "G3 mixed timed/rep circuit with kg bell",
            // x4 applies to all three; 40 s / 30 s are per-set durations; 24 (kg) load.
            input: "circuit x4: 40s battle ropes, 10 KB swings @ 24kg, 30s wall sit",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Battle Ropes", setCount: 4, durationSeconds: 40),
                ExpectedExercise(name: "Kettlebell Swings", setCount: 4, reps: 10, weight: 24, weightUnit: .kg),
                ExpectedExercise(name: "Wall Sit", setCount: 4, durationSeconds: 30)
            ])
        ),
        WorkoutParseEvalCase(
            name: "G4 unilateral each side with load",
            input: "single arm DB row 3x10 each side @ 70",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Single Arm Dumbbell Row", setCount: 3, reps: 10, weight: 70, weightUnit: .lb)
            ])
        ),

        // MARK: - H. Warmups

        WorkoutParseEvalCase(
            name: "H1 unquantified warmup is not a set",
            // "warmed up with the bar" has no count → only the 3 working sets log.
            input: "warmed up with the bar then did 3 working sets of 5 at 185 on bench",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Bench", setCount: 3, reps: 5, weight: 185, weightUnit: .lb)
            ])
        ),

        // MARK: - I. Dated headers + titles

        WorkoutParseEvalCase(
            name: "I1 weekday abbreviation header with title",
            // "Mon" on Wed 2025-01-15 → 2025-01-13. Title "Legs".
            input: """
            Mon - Legs
            squat 4x6 @ 245
            leg ext 3x12 @ 90
            """,
            tier: .prose,
            expected: ExpectedWorkout(
                title: "Legs",
                month: 1,
                day: 13,
                year: 2025,
                exercises: [
                    ExpectedExercise(name: "Squat", setCount: 4, reps: 6, weight: 245, weightUnit: .lb),
                    ExpectedExercise(name: "Leg Extension", setCount: 3, reps: 12, weight: 90, weightUnit: .lb)
                ]
            )
        ),
        WorkoutParseEvalCase(
            name: "I2 title then slash date",
            // "1/10" → 2025-01-10 (on/before reference day).
            input: """
            Upper Body — 1/10
            bench 3x8 @ 175
            rows 3x10 @ 135
            """,
            tier: .prose,
            expected: ExpectedWorkout(
                title: "Upper Body",
                month: 1,
                day: 10,
                year: 2025,
                exercises: [
                    ExpectedExercise(name: "Bench", setCount: 3, reps: 8, weight: 175, weightUnit: .lb),
                    ExpectedExercise(name: "Rows", setCount: 3, reps: 10, weight: 135, weightUnit: .lb)
                ]
            )
        ),
        WorkoutParseEvalCase(
            name: "I3 full weekday with inline title and prose sets",
            // "Saturday" → 2025-01-11. Title "Back Day" (case-insensitive compare).
            input: "Saturday: back day. deadlift 3x5 @ 335, lat pulldown 3x10 @ 140",
            tier: .prose,
            expected: ExpectedWorkout(
                title: "Back Day",
                month: 1,
                day: 11,
                year: 2025,
                exercises: [
                    ExpectedExercise(name: "Deadlift", setCount: 3, reps: 5, weight: 335, weightUnit: .lb),
                    ExpectedExercise(name: "Lat Pulldown", setCount: 3, reps: 10, weight: 140, weightUnit: .lb)
                ]
            )
        ),
        WorkoutParseEvalCase(
            name: "I4 month-name date header",
            // "Jan 12" → 2025-01-12.
            input: """
            Jan 12 - Full Body
            goblet squat 3x12 @ 50
            push ups 3x15
            """,
            tier: .prose,
            expected: ExpectedWorkout(
                title: "Full Body",
                month: 1,
                day: 12,
                year: 2025,
                exercises: [
                    ExpectedExercise(name: "Goblet Squat", setCount: 3, reps: 12, weight: 50, weightUnit: .lb),
                    ExpectedExercise(name: "Push Ups", setCount: 3, reps: 15)
                ]
            )
        ),
        WorkoutParseEvalCase(
            name: "I5 dictated 'two days ago'",
            // "two days ago" → 2025-01-13 (daysAgo path in resolveDateText).
            input: "two days ago i did incline bench four sets of eight at one fifty five",
            tier: .prose,
            expected: ExpectedWorkout(
                month: 1,
                day: 13,
                year: 2025,
                exercises: [
                    ExpectedExercise(name: "Incline Bench", setCount: 4, reps: 8, weight: 155, weightUnit: .lb)
                ]
            )
        ),

        // MARK: - J. Typos

        WorkoutParseEvalCase(
            name: "J1 typos and 'x5 x5'",
            // "squats x5 x5" = 5x5. Typo'd names resolve via the matcher's edit tolerance.
            input: """
            bench pres 3x8 @ 185
            squats x5 x5 @ 225
            deadlfit 1x5 @ 315
            """,
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Bench Press", setCount: 3, reps: 8, weight: 185, weightUnit: .lb),
                ExpectedExercise(name: "Squats", setCount: 5, reps: 5, weight: 225, weightUnit: .lb),
                ExpectedExercise(name: "Deadlift", setCount: 1, reps: 5, weight: 315, weightUnit: .lb)
            ])
        ),
        WorkoutParseEvalCase(
            name: "J2 misspelled name with glued unit",
            input: "tricep extentions 3 sets 12 reps 40lbs",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Triceps Extension", setCount: 3, reps: 12, weight: 40, weightUnit: .lb)
            ])
        ),
        WorkoutParseEvalCase(
            name: "J3 transposed letters and bare trailing load",
            input: "romanain deadlifts 3x10 135",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Romanian Deadlift", setCount: 3, reps: 10, weight: 135, weightUnit: .lb)
            ])
        ),

        // MARK: - K. Non-English (loanword movement names so the name check is fair)

        WorkoutParseEvalCase(
            name: "K1 [ES] Spanish log with loanword names",
            // "4 series de 10 con 100 kg" = 4x10 @ 100. "curl de bíceps" resolves to
            // Biceps Curl whether kept or translated. "ayer" is NOT asserted: the date
            // resolver has no Spanish words.
            input: "ayer hice hip thrust 4 series de 10 con 100 kg y curl de bíceps 3 series de 12 con 12 kg",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Hip Thrust", setCount: 4, reps: 10, weight: 100, weightUnit: .kg),
                ExpectedExercise(name: "Biceps Curl", setCount: 3, reps: 12, weight: 12, weightUnit: .kg)
            ])
        ),
        WorkoutParseEvalCase(
            name: "K2 [DE] German log with loanword names",
            // "4 Sätze à 6 Wdh." = 4 sets × 6 reps. "10 kg Zusatzgewicht" = added load 10.
            // Title/date ("Heute Push") intentionally unchecked.
            input: "Heute Push: Bench 4 Sätze à 6 Wdh. mit 90 kg, danach Dips 3x12 mit 10 kg Zusatzgewicht",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Bench", setCount: 4, reps: 6, weight: 90, weightUnit: .kg),
                ExpectedExercise(name: "Dips", setCount: 3, reps: 12, weight: 10, weightUnit: .kg)
            ])
        ),

        // MARK: - L. User default = kg (weights written without a unit)

        WorkoutParseEvalCase(
            name: "L1 kg default: dictated unit-less load",
            // "one hundred" with no unit → the user's default, kg.
            input: "squats five sets of five at one hundred",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Squat", setCount: 5, reps: 5, weight: 100, weightUnit: .kg)
            ]),
            defaultWeightUnit: .kg
        ),
        WorkoutParseEvalCase(
            name: "L2 kg default: plain notation without unit",
            input: "Bench 3x8 @ 80\nRows 3x10 @ 70",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Bench", setCount: 3, reps: 8, weight: 80, weightUnit: .kg),
                ExpectedExercise(name: "Rows", setCount: 3, reps: 10, weight: 70, weightUnit: .kg)
            ]),
            defaultWeightUnit: .kg
        ),
        WorkoutParseEvalCase(
            name: "L3 kg default with explicit lb override",
            // Unit-less 180 → kg; "30 lb" is written, so it stays lb.
            input: "Deadlift 3x5 @ 180\nDB curls 3x12 @ 30 lb",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Deadlift", setCount: 3, reps: 5, weight: 180, weightUnit: .kg),
                ExpectedExercise(name: "Dumbbell Curls", setCount: 3, reps: 12, weight: 30, weightUnit: .lb)
            ]),
            defaultWeightUnit: .kg
        ),
        WorkoutParseEvalCase(
            name: "L4 kg default: dictation with weighted dips 'plus twenty'",
            // "plus twenty" = 20 added load, in the default unit (kg).
            input: "overhead press four sets of six at fifty then dips three sets of ten plus twenty",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Overhead Press", setCount: 4, reps: 6, weight: 50, weightUnit: .kg),
                ExpectedExercise(name: "Dips", setCount: 3, reps: 10, weight: 20, weightUnit: .kg)
            ]),
            defaultWeightUnit: .kg
        ),
        WorkoutParseEvalCase(
            name: "L5 kg default: bullets, last line in lb",
            input: """
            • RDL 3x8 @ 120
            • leg press 4x12 @ 200
            • calf raise 3x15 @ 100 lb
            """,
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Romanian Deadlift", setCount: 3, reps: 8, weight: 120, weightUnit: .kg),
                ExpectedExercise(name: "Leg Press", setCount: 4, reps: 12, weight: 200, weightUnit: .kg),
                ExpectedExercise(name: "Calf Raise", setCount: 3, reps: 15, weight: 100, weightUnit: .lb)
            ]),
            defaultWeightUnit: .kg
        ),
        WorkoutParseEvalCase(
            name: "L6 kg default: worked up, per-set",
            // 60x5, 80x3, 100x1, all kg.
            input: "worked up 60 80 100 for 5 3 1 on bench",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Bench", setCount: 3, reps: 5, weight: 60, weightUnit: .kg, perSetReps: [5, 3, 1], perSetWeights: [60, 80, 100])
            ]),
            defaultWeightUnit: .kg
        ),
        WorkoutParseEvalCase(
            name: "L7 kg default: decimal load and kettlebell carry",
            // "the 24" = the 24 kg bell; "40m" is carry distance, 32 kg load.
            input: "OHP 5x5 at 42.5\nkettlebell swings 3x20 with the 24\nfarmer carry 3x40m with 32s",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Overhead Press", setCount: 5, reps: 5, weight: 42.5, weightUnit: .kg),
                ExpectedExercise(name: "Kettlebell Swings", setCount: 3, reps: 20, weight: 24, weightUnit: .kg),
                ExpectedExercise(name: "Farmer Carry", setCount: 3, weight: 32, weightUnit: .kg, distance: 40, distanceUnit: .meters)
            ]),
            defaultWeightUnit: .kg
        ),
        WorkoutParseEvalCase(
            name: "L8 kg default: dictated 'pounds' overrides",
            // "pounds" is written → lb despite the kg preference; the unit-less 60 → kg.
            input: "hip thrusts three sets of ten at two twenty five pounds then lunges three sets of eight at sixty",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Hip Thrusts", setCount: 3, reps: 10, weight: 225, weightUnit: .lb),
                ExpectedExercise(name: "Lunges", setCount: 3, reps: 8, weight: 60, weightUnit: .kg)
            ]),
            defaultWeightUnit: .kg
        ),

        // MARK: - M. Real inputs the deterministic parser mangles

        WorkoutParseEvalCase(
            name: "M1 weight-first triple 225x5x3",
            // Leading 225 can only be the load; weight×reps×sets → 3 sets of 5.
            // Least certain expectation in the file (see header).
            input: "Bench 225x5x3",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Bench", setCount: 3, reps: 5, weight: 225, weightUnit: .lb)
            ])
        ),
        WorkoutParseEvalCase(
            name: "M2 top sets then back-off sets, same lift",
            // One Squat entry: 3x5 @ 315 then 2x8 @ 275 → 5 sets.
            input: "Squat 3x5 at 315 then backoff 2x8 at 275",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Squat", setCount: 5, reps: 5, weight: 315, weightUnit: .lb, perSetReps: [5, 5, 5, 8, 8], perSetWeights: [315, 315, 315, 275, 275])
            ])
        ),
        WorkoutParseEvalCase(
            name: "M3 kg lead then unit-less back-offs",
            // "80" inherits kg from this exercise's "100kg". 5x5 + 3x10 → 8 sets.
            input: "Squat 100kg 5x5 then 3x10 at 80",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Squat", setCount: 8, reps: 5, weight: 100, weightUnit: .kg, perSetReps: [5, 5, 5, 5, 5, 10, 10, 10], perSetWeights: [100, 100, 100, 100, 100, 80, 80, 80])
            ])
        ),
        WorkoutParseEvalCase(
            name: "M4 comma-joined lines, '60s' dumbbells",
            // "60s" after an incline DB press = 60 lb dumbbells, not 60 seconds.
            input: "bench 3x8 185, incline db 3x10 60s",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Bench", setCount: 3, reps: 8, weight: 185, weightUnit: .lb),
                ExpectedExercise(name: "Incline Dumbbell Press", setCount: 3, reps: 10, weight: 60, weightUnit: .lb)
            ])
        ),
        WorkoutParseEvalCase(
            name: "M5 two squat variants stay separate",
            // Front vs back squat are distinct movements (matcher scores them 0.5 → fails
            // if swapped or merged).
            input: "Front squat 3x5 @ 60 kg, back squat 3x5 @ 100 kg",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Front Squat", setCount: 3, reps: 5, weight: 60, weightUnit: .kg),
                ExpectedExercise(name: "Back Squat", setCount: 3, reps: 5, weight: 100, weightUnit: .kg)
            ])
        ),
        WorkoutParseEvalCase(
            name: "M6 mile run then pushups",
            // 1 mile, 8 min = 480 s. Name "Pushups" as written ("Push-ups" fails the
            // matcher — limitation 6).
            input: "Ran a mile in 8 minutes then 3 sets of 20 pushups",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Run", setCount: 1, durationSeconds: 480, distance: 1, distanceUnit: .miles),
                ExpectedExercise(name: "Pushups", setCount: 3, reps: 20)
            ])
        ),
        WorkoutParseEvalCase(
            name: "M7 bike minutes then pushups",
            input: "Did 20 minutes on the bike then 3x10 pushups",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Bike", setCount: 1, durationSeconds: 1200),
                ExpectedExercise(name: "Pushups", setCount: 3, reps: 10)
            ])
        ),
        WorkoutParseEvalCase(
            name: "M8 title, notation line, then prose line with 'the 60s'",
            input: "Push day\nBench 3x8 @ 185\nThen incline dumbbell press, three sets of ten with the 60s",
            tier: .prose,
            expected: ExpectedWorkout(
                title: "Push day",
                exercises: [
                    ExpectedExercise(name: "Bench", setCount: 3, reps: 8, weight: 185, weightUnit: .lb),
                    ExpectedExercise(name: "Incline Dumbbell Press", setCount: 3, reps: 10, weight: 60, weightUnit: .lb)
                ]
            )
        ),
        WorkoutParseEvalCase(
            name: "M9 notation line then prose variant line",
            // Close-grip bench is its own entry (matcher: "Bench" vs "Close Grip Bench"
            // scores 0.5, so a merge or mislabel fails).
            input: "Bench 3x8 @ 185\nthen close grip bench, three sets of ten at 135",
            tier: .prose,
            expected: ExpectedWorkout(exercises: [
                ExpectedExercise(name: "Bench", setCount: 3, reps: 8, weight: 185, weightUnit: .lb),
                ExpectedExercise(name: "Close Grip Bench", setCount: 3, reps: 10, weight: 135, weightUnit: .lb)
            ])
        )
    ]
}
