import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Structures workout text with Apple's on-device language model (Apple Intelligence),
/// reconciled against the deterministic parser. Everything runs on device, so the
/// local-only privacy posture is preserved; nothing is sent off the phone.
///
/// Division of labor (same doctrine as `TrainingInsights`): the model only *reads* —
/// it segments the text into exercises, normalizes names, and reports counts and values
/// it saw written. All arithmetic stays in code: set expansion (`setCount` → N drafts),
/// date resolution, and unit mapping are deterministic. A ~3B model asked to emit
/// "3x8" as three identical array elements reliably emits one; asked for `setCount: 3`
/// it is dependable.
///
/// The deterministic parser always runs too, and `WorkoutDraftArbiter` picks whichever
/// draft is more faithful to the source text — so notation input ("Bench 3x8 @ 185")
/// keeps its exact deterministic parse, and the model only wins where it adds value
/// (conversational prose the notation parser cannot read).
nonisolated struct FoundationModelsWorkoutScanParser: WorkoutScanParsing {
    private let fallback: WorkoutScanParsing

    init(fallback: WorkoutScanParsing = HeuristicWorkoutScanParser()) {
        self.fallback = fallback
    }

    /// True only when the on-device model is ready to use right now.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        return false
        #else
        return false
        #endif
    }

    /// Loads the model into memory ahead of the first parse so the processing phase
    /// doesn't pay model-load latency. Call when an entry sheet appears; a no-op when
    /// the model is unavailable.
    /// Workout text is the user's own content being transformed, not open-ended
    /// generation — the exact use case Apple's relaxed guardrail mode exists for.
    /// Default guardrails refuse benign gym prose ("leg day: squats five sets of
    /// five") as "may contain sensitive content".
    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    static var transformationModel: SystemLanguageModel {
        SystemLanguageModel(guardrails: .permissiveContentTransformations)
    }
    #endif

    static func prewarm() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            LanguageModelSession(model: transformationModel, instructions: instructions).prewarm()
        }
        #endif
    }

    func parse(ocrText: String, referenceDate: Date) async -> ParsedWorkoutDraft {
        let deterministic = await fallback.parse(ocrText: ocrText, referenceDate: referenceDate)

        var candidates: [ParsedWorkoutDraft?] = []
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            // Two independent model readings: a rewrite into gym notation that the
            // deterministic parser then parses, and direct structured extraction.
            // The rewrite is the simpler task and its numbers pass through the
            // deterministic parser, so it gets tie priority (candidate order);
            // the arbiter scores both against the source text.
            candidates.append(await rewriteAndParse(ocrText: ocrText, referenceDate: referenceDate))
            candidates.append(await generate(ocrText: ocrText, referenceDate: referenceDate))
        }
        #endif

        return WorkoutDraftArbiter.choose(
            deterministic: deterministic,
            candidates: candidates,
            sourceText: ocrText
        )
    }

    /// Task definition, output policy, and a one-shot example live in the instructions
    /// (they outrank per-request prompt content); the per-request prompt carries only
    /// the workout text. The example is the highest-leverage line: it shows setCount
    /// staying a count and per-set arrays appearing only for genuinely varied sets.
    static let instructions = """
        You extract structured workout data from a user's workout log — typed notes, \
        dictation, or a photographed page. Rules:
        - Only report what is written. Never invent exercises, sets, weights, or reps. \
        Leave a field nil when the text does not state it.
        - Exactly one exercises entry per distinct movement, in the order written. \
        Never split one movement into two entries; never merge two movements into one.
        - name is the movement itself ("Bench Press", "Squat", "Run") — never a \
        phrase like "worked up to" or a whole sentence.
        - setCount is the NUMBER of sets: "3x8", "3 sets of 8", "three sets of \
        eight", and "5 by 5" all mean setCount N with reps R (3/8, 3/8, 3/8, 5/5). \
        "3 rounds of 10 pushups, 15 squats" means EVERY movement in the round gets \
        setCount 3: pushups setCount 3 reps 10, squats setCount 3 reps 15.
        - "@ 185", "at 185", "185 lb" is the weight. "100kg" is kilograms. \
        "worked up to 225 for a double" means one top set of the named exercise: \
        setCount 1, weight 225, reps 2 (a single is 1 rep, a double 2, a triple 3).
        - Report weight and distance numbers exactly as written — never convert \
        units: "5 kilometers" → distance 5, distanceUnit "km"; "3 miles" → 3 "mi".
        - durationSeconds and restSeconds are always SECONDS: "45 seconds" → 45, \
        "in 25 minutes" → 1500, "rest 2 min" → restSeconds 120. durationSeconds is \
        the length of ONE set or effort, never the whole session. When a header \
        gives a total time AND the sets have their own time ("20 minute plank \
        circuit, 3 planks of 45 seconds each"), use the per-set time: setCount 3, \
        durationSeconds 45 — the 20 minutes is ignored.
        - For a rep range like "8-12" or "8–10", use the lower bound (8).
        - "4 x 20-meter accelerations" is DISTANCE work: setCount 4, distance 20, \
        distanceUnit "m", reps nil. A number attached to meters/km/miles is never \
        reps.
        - Percentages like "at 85-90%" are effort intensity — ignore them entirely; \
        never a weight, reps, or distance. "each leg" / "each side" does not change \
        setCount or reps. "with 20-pound dumbbells" → weight 20, weightUnit "lb".
        - Use perSetWeights/perSetReps ONLY when the sets differ from each other: \
        "Bench 135x5 155x3 175x1" → setCount 3, perSetWeights [135, 155, 175], \
        perSetReps [5, 3, 1]. Otherwise leave them nil.
        - Expand equipment shorthand in names: "DB" → Dumbbell, "BB" → Barbell, \
        "KB" → Kettlebell.
        Example — "Push day yesterday. Bench press 3x8 @ 185, rest 90s, then incline \
        DB press three sets of ten at 60" becomes: title "Push day", dateText \
        "yesterday", exercises [ {name "Bench Press", setCount 3, reps 8, weight 185, \
        weightUnit "lb", restSeconds 90}, {name "Incline Dumbbell Press", setCount 3, \
        reps 10, weight 60, weightUnit "lb"} ].
        """

    /// The rewrite pass asks for one thing only: the same workout as standard
    /// notation lines, numbers verbatim. Transliteration is squarely inside the
    /// small model's competence, and the deterministic parser then owns all the
    /// numeric structure — the same division of labor as everywhere else.
    static let rewriteInstructions = """
        You convert a user's workout log into standard gym notation, one line per \
        distinct movement, in the order written. Use the same numbers that appear \
        in the log; write number words as digits ("three" → 3, "a double" → 2 \
        reps). Do not add movements or numbers, and do not leave any movement out.
        Line formats:
        - Strength: "Name SETSxREPS @ WEIGHT unit" → "Bench Press 3x8 @ 185 lb". \
        Omit "@ WEIGHT unit" when no weight is stated.
        - Different weights per set: "Name W1xR1 W2xR2" → "Bench 135x5 155x3".
        - Timed sets: "Name SETSxSECONDSs" → "Plank 3x45s".
        - Cardio: "Name DISTANCEunit MM:SS" → "Run 5km 25:00".
        - Rest between sets: append "rest Ns" → "Squat 5x5 @ 225 lb rest 90s".
        - Sprints/drills over a distance: "Name SETSxDISTANCEm" → "4 × 20-meter \
        accelerations at 85-90%" becomes "Accelerations 4x20m".
        Rules: "3 rounds of 10 pushups, 15 squats" → "Pushups 3x10" and "Squats \
        3x15". "worked up to 225 on bench for a double" → "Bench 1x2 @ 225 lb". \
        Drop intensity percentages ("at 85-90%") and "each leg"/"each side" — they \
        are not numbers for the line. "with 20-pound dumbbells" → "@ 20 lb". \
        Expand shorthand: "DB" → Dumbbell, "BB" → Barbell, "KB" → Kettlebell.
        Example — "I did three sets of eight on bench at 185, then some curls, 3 \
        sets of 10 with 25 pound dumbbells, resting about 90 seconds" → dateText \
        "", lines ["Bench 3x8 @ 185 lb rest 90s", "Dumbbell Curl 3x10 @ 25 lb rest 90s"].
        """

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    func rewriteAndParse(ocrText: String, referenceDate: Date) async -> ParsedWorkoutDraft? {
        // Refusals on benign gym text are intermittent (the same input passes on
        // retry), so one fresh-session retry meaningfully raises the hit rate.
        for _ in 0..<2 {
            if let draft = await rewriteOnce(ocrText: ocrText, referenceDate: referenceDate) {
                return draft
            }
        }
        return nil
    }

    @available(iOS 26.0, *)
    private func rewriteOnce(ocrText: String, referenceDate: Date) async -> ParsedWorkoutDraft? {
        let session = LanguageModelSession(model: Self.transformationModel, instructions: Self.rewriteInstructions)
        let prompt = "Convert this workout to notation lines:\n\n\(ocrText)"

        do {
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedNotation.self,
                options: GenerationOptions(sampling: .greedy)
            )
            let notation = response.content
            let text = notation.lines.joined(separator: "\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            var draft = HandwrittenWorkoutParser.parse(text, referenceDate: referenceDate)
            if draft.performedAt == nil {
                draft.performedAt = GeneratedWorkout.resolveDate(notation.dateText, referenceDate: referenceDate)
            }
            return draft.hasContent ? draft : nil
        } catch {
            return nil
        }
    }

    @available(iOS 26.0, *)
    func generate(ocrText: String, referenceDate: Date) async -> ParsedWorkoutDraft? {
        // Same intermittent-refusal reality as the rewrite pass: one fresh-session
        // retry meaningfully raises the hit rate.
        for _ in 0..<2 {
            if let draft = await generateOnce(ocrText: ocrText, referenceDate: referenceDate) {
                return draft
            }
        }
        return nil
    }

    @available(iOS 26.0, *)
    private func generateOnce(ocrText: String, referenceDate: Date) async -> ParsedWorkoutDraft? {
        let session = LanguageModelSession(model: Self.transformationModel, instructions: Self.instructions)
        let prompt = "Extract the structured workout from this text:\n\n\(ocrText)"

        do {
            // Greedy decoding: extraction wants the single most likely reading, not
            // creative variety — and the same text should parse the same way twice.
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedWorkout.self,
                options: GenerationOptions(sampling: .greedy)
            )
            let draft = response.content.draft(referenceDate: referenceDate)
            // The model occasionally returns nothing usable; the arbiter treats nil
            // as "deterministic parser wins".
            return draft.hasContent ? draft : nil
        } catch {
            return nil
        }
    }
    #endif
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
nonisolated struct GeneratedNotation {
    @Guide(description: "The workout's date exactly as written, e.g. \"7/22\" or \"yesterday\". Empty if no date is mentioned.")
    var dateText: String
    @Guide(description: "One gym-notation line per distinct movement, e.g. \"Bench Press 3x8 @ 185 lb rest 90s\".")
    var lines: [String]
}

@available(iOS 26.0, *)
@Generable
nonisolated struct GeneratedWorkout {
    @Guide(description: "Title or focus written in the text, e.g. \"Push Day\". Empty if none.")
    var title: String
    @Guide(description: "The workout's date exactly as written, e.g. \"7/22\", \"2026-07-22\", or \"yesterday\". Empty if no date is mentioned.")
    var dateText: String
    @Guide(description: "Every distinct exercise, in the order written.")
    var exercises: [GeneratedExercise]

    func draft(referenceDate: Date) -> ParsedWorkoutDraft {
        let mapped = exercises.compactMap { $0.draft() }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedWorkoutDraft(
            performedAt: Self.resolveDate(dateText, referenceDate: referenceDate),
            title: cleanTitle.isEmpty ? "Scanned workout" : cleanTitle,
            exercises: mapped
        )
    }

    /// Calendar math stays out of the model: it reports the date *text* and code
    /// resolves it — relative words directly, explicit forms via the deterministic
    /// parser's date rules.
    static func resolveDate(_ text: String, referenceDate: Date) -> Date? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return nil }
        if cleaned.contains("today") || cleaned.contains("this morning") || cleaned.contains("tonight") {
            return referenceDate
        }
        if cleaned.contains("yesterday") || cleaned.contains("last night") {
            return Calendar.current.date(byAdding: .day, value: -1, to: referenceDate)
        }
        return HandwrittenWorkoutParser.explicitDate(in: cleaned, referenceDate: referenceDate)
    }
}

@available(iOS 26.0, *)
@Generable
nonisolated struct GeneratedExercise {
    // Name first: generation follows declaration order, and the name anchors the
    // numeric fields that follow it.
    @Guide(description: "The exercise name, e.g. \"Bench Press\" or \"Run\".")
    var name: String
    @Guide(description: "How many sets were performed. \"3x8\" and \"three sets of eight\" both mean 3. 1 if the text implies a single effort.", .range(1...20))
    var setCount: Int
    @Guide(description: "Reps per set; the lower bound for a range like \"8-12\". Nil when not stated.")
    var reps: Int?
    @Guide(description: "Weight in the unit the user wrote. Nil for bodyweight or unstated.")
    var weight: Double?
    @Guide(description: "Unit of the weight.", .anyOf(["lb", "kg", "bodyweight", "unknown"]))
    var weightUnit: String
    @Guide(description: "Rest between sets in seconds. Nil when not stated.")
    var restSeconds: Int?
    @Guide(description: "Duration in seconds of one set or effort, for timed/cardio work. Nil otherwise.")
    var durationSeconds: Int?
    @Guide(description: "Distance for cardio work, in the unit the user wrote. Nil otherwise.")
    var distance: Double?
    @Guide(description: "Unit of the distance.", .anyOf(["km", "mi", "m", "yd", "ft", "none"]))
    var distanceUnit: String
    @Guide(description: "Weights per set, ONLY when sets differ (\"135x5 155x3\" → [135, 155]). Nil when uniform.")
    var perSetWeights: [Double]?
    @Guide(description: "Reps per set, ONLY when sets differ (\"135x5 155x3\" → [5, 3]). Nil when uniform.")
    var perSetReps: [Int]?

    /// The model reported counts and values; the expansion into N set drafts is
    /// plain code, mirroring the deterministic parser's `buildSets`.
    func draft() -> ParsedExerciseDraft? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return nil }

        let unit: WeightUnit = weightUnit.lowercased().hasPrefix("k") ? .kg : .lb
        let bodyweight = weightUnit == "bodyweight"
        let uniformWeight = bodyweight ? nil : normalized(weight)
        let uniformReps = normalized(reps)
        let uniformRest = normalized(restSeconds)
        let uniformDuration = normalized(durationSeconds)
        let uniformDistance = normalized(distance)

        let variedWeights = perSetWeights?.compactMap(normalized) ?? []
        let variedReps = perSetReps?.compactMap(normalized) ?? []
        let variedCount = max(variedWeights.count, variedReps.count)
        // The model sometimes stuffs a single uniform value into a per-set array
        // ("with a 50 lb dumbbell" → perSetWeights [50]); never let that shrink the
        // set count below what it reported.
        let count = min(max(setCount, variedCount, 1), 20)

        let sets = (0..<count).map { index in
            ParsedSetDraft(
                weight: variedWeights.indices.contains(index) ? variedWeights[index] : (variedWeights.last ?? uniformWeight),
                weightUnit: unit,
                reps: variedReps.indices.contains(index) ? variedReps[index] : (variedReps.last ?? uniformReps),
                distance: uniformDistance,
                distanceUnit: Self.distanceUnit(from: distanceUnit),
                durationSeconds: uniformDuration,
                restSeconds: uniformRest
            )
        }

        // Keep value-less sets ("3 sets to failure") — the review screen lets the
        // user fill reps in; dropping them silently shrank workouts in the old design.
        return ParsedExerciseDraft(name: cleanName, sets: sets)
    }

    /// Constrained decoding forces a value into every non-nil numeric slot, so treat
    /// non-positive numbers as "not stated" rather than importing zeros.
    private func normalized(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private func normalized(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func distanceUnit(from raw: String) -> DistanceUnit {
        switch raw.lowercased().trimmingCharacters(in: .whitespaces) {
        case "km", "k", "kilometer", "kilometers": return .kilometers
        case "mi", "mile", "miles": return .miles
        case "yd", "yard", "yards": return .yards
        case "ft", "feet", "foot": return .feet
        default: return .meters
        }
    }
}
#endif
