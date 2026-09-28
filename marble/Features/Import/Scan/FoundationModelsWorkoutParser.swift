import Foundation
import Synchronization

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
    /// Why the most recent parse ended without any model reading, for the UI to
    /// explain a notation-only result. `nil` means the model contributed a
    /// candidate (whether or not the arbiter picked it), answered with nothing
    /// usable, or no parse has run yet.
    nonisolated enum ModelIssue: Equatable, Sendable {
        /// Apple Intelligence isn't usable right now: not supported or not
        /// enabled on this device, model assets missing or updating, or a recent
        /// hard failure put the model on cool-down (`ModelCircuitBreaker`).
        case unavailable
        /// The text doesn't fit the model's context window, so the notation
        /// parser read it alone. One session at a time fits.
        case inputTooLong
        /// The model doesn't support the device's current language/locale.
        case unsupportedLanguage
        /// The model ran but every attempt failed (refusal, decoding, timeout…).
        case failed
    }

    /// How one model call failed. Only the transient kinds are worth a second
    /// attempt: decoding is greedy, so repeating a deterministic failure just
    /// doubles the wait.
    nonisolated enum ModelFailure: Equatable, Sendable {
        case guardrailViolation
        case refusal
        case rateLimited
        case concurrentRequests
        case contextWindowExceeded
        case unsupportedLanguage
        case unsupportedGuide
        case assetsUnavailable
        case decodingFailure
        case timeout
        case cancelled
        case unknown

        /// Guardrail and refusal verdicts on benign gym text are intermittent
        /// (the same input passes in a fresh session), and rate limits and
        /// concurrent-request errors clear on their own.
        var isRetryable: Bool {
            switch self {
            case .guardrailViolation, .refusal, .rateLimited, .concurrentRequests: true
            default: false
            }
        }

        /// Failures that mean "the model itself is broken right now": missing
        /// assets (seen during OS asset updates, and on simulators whose
        /// availability check passes while every call throws) and errors the
        /// framework doesn't classify. Every further call would fail the same way.
        var tripsCircuitBreaker: Bool {
            self == .assetsUnavailable || self == .unknown
        }

        /// What the UI should say about it; cancellation is not an issue.
        var issue: ModelIssue? {
            switch self {
            case .contextWindowExceeded: .inputTooLong
            case .unsupportedLanguage: .unsupportedLanguage
            case .assetsUnavailable: .unavailable
            case .cancelled: nil
            default: .failed
            }
        }
    }

    private let fallback: WorkoutScanParsing
    /// Unit assumed for weights written without one, passed to every
    /// deterministic re-parse (fallback and notation-rewrite) and to the model's
    /// "unknown" unit, so the user's preferred unit reaches every candidate.
    private let defaultWeightUnit: WeightUnit
    private let breaker: ModelCircuitBreaker
    private let report = IssueReport()

    init(
        fallback: WorkoutScanParsing? = nil,
        defaultWeightUnit: WeightUnit = .lb,
        breaker: ModelCircuitBreaker = .shared
    ) {
        self.fallback = fallback ?? HeuristicWorkoutScanParser(defaultWeightUnit: defaultWeightUnit)
        self.defaultWeightUnit = defaultWeightUnit
        self.breaker = breaker
    }

    /// The issue recorded by this parser's most recent `parse` (copies of the
    /// parser share it). Read it after `parse` returns; with concurrent parses
    /// on one parser, the last to finish wins.
    var lastModelIssue: ModelIssue? { report.issue }

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

    /// Loads the model into memory ahead of the first parse so the processing phase
    /// doesn't pay model-load latency. Call only after a strong near-term signal,
    /// such as focused typing in the workout editor; a no-op when unavailable.
    /// Warms what pass 1 (the notation rewrite) uses — its instructions plus the
    /// fixed prompt lead-in — and hands that session to the first rewrite that
    /// starts while it is fresh, so the cached prefix isn't thrown away.
    static func prewarm() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability,
           SystemLanguageModel.default.supportsLocale() {
            let session = LanguageModelSession(model: transformationModel, instructions: rewriteInstructions)
            session.prewarm(promptPrefix: Prompt(rewritePromptPrefix))
            Task { await PrewarmedRewriteSession.shared.store(session) }
        }
        #endif
    }

    func parse(ocrText: String, referenceDate: Date) async -> ParsedWorkoutDraft {
        await parse(ocrText: ocrText, referenceDate: referenceDate) { _ in }
    }

    /// Reports each pipeline stage so the processing UI can show real progress:
    /// the deterministic pass, then each on-device model reading, then the
    /// reconcile/library-match wrap-up.
    func parse(
        ocrText: String,
        referenceDate: Date,
        onStage: @Sendable (WorkoutParseStage) async -> Void
    ) async -> ParsedWorkoutDraft {
        await onStage(.readingNotation)
        let deterministic = await fallback.parse(ocrText: ocrText, referenceDate: referenceDate)

        var candidates: [ParsedWorkoutDraft?] = []
        var issue: ModelIssue? = .unavailable
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            (candidates, issue) = await modelCandidates(ocrText: ocrText, referenceDate: referenceDate, onStage: onStage)
        }
        #endif
        report.issue = issue

        await onStage(.finalizing)
        return WorkoutDraftArbiter.choose(
            deterministic: deterministic,
            candidates: candidates,
            sourceText: ocrText,
            defaultWeightUnit: defaultWeightUnit
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
        - weightUnit is "lb" or "kg" only when the text writes the unit (lb, lbs, \
        pounds, kg, kilos); a bare number like "at 185" is weightUnit "unknown".
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
        DB press three sets of ten at 60 pounds" becomes: title "Push day", dateText \
        "yesterday", exercises [ {name "Bench Press", setCount 3, reps 8, weight 185, \
        weightUnit "unknown", restSeconds 90}, {name "Incline Dumbbell Press", \
        setCount 3, reps 10, weight 60, weightUnit "lb"} ].
        """

    /// The rewrite pass asks for one thing only: the same workout as standard
    /// notation lines, numbers verbatim. Transliteration is squarely inside the
    /// small model's competence, and the deterministic parser then owns all the
    /// numeric structure — the same division of labor as everywhere else. Units
    /// are copied only when written, so a bare "185" reaches the parser bare and
    /// takes the user's preferred unit; RPE stays on the line for the parser.
    static let rewriteInstructions = """
        You convert a user's workout log into standard gym notation, one line per \
        distinct movement, in the order written. Use the same numbers that appear \
        in the log; write number words as digits ("three" → 3, "a double" → 2 \
        reps). Do not add movements or numbers, and do not leave any movement out.
        Line formats:
        - Strength: "Name SETSxREPS @ WEIGHT" → "Bench Press 3x8 @ 185". Add a \
        unit only when the log writes one: "185 pounds" → "@ 185 lb", "100 kilos" \
        → "@ 100 kg". Omit "@ WEIGHT" when no weight is stated.
        - Different weights per set: "Name W1xR1 W2xR2" → "Bench 135x5 155x3".
        - Timed sets: "Name SETSxSECONDSs" → "Plank 3x45s".
        - Cardio: "Name DISTANCEunit MM:SS" → "Run 5km 25:00".
        - Rest between sets: append "rest Ns" → "Squat 5x5 @ 225 rest 90s".
        - Effort ratings: copy "RPE 8" or "@8" exactly as written at the end of \
        the line → "Squat 5x5 @ 225 RPE 8".
        - Sprints/drills over a distance: "Name SETSxDISTANCEm" → "4 × 20-meter \
        accelerations at 85-90%" becomes "Accelerations 4x20m".
        Rules: "3 rounds of 10 pushups, 15 squats" → "Pushups 3x10" and "Squats \
        3x15". "worked up to 225 on bench for a double" → "Bench 1x2 @ 225". \
        Drop intensity percentages ("at 85-90%") and "each leg"/"each side" — they \
        are not numbers for the line. "with 20-pound dumbbells" → "@ 20 lb". \
        Expand shorthand: "DB" → Dumbbell, "BB" → Barbell, "KB" → Kettlebell.
        Example — "I did three sets of eight on bench at 185, then some curls, 3 \
        sets of 10 with 25 pound dumbbells, resting about 90 seconds" → dateText \
        "", lines ["Bench 3x8 @ 185 rest 90s", "Dumbbell Curl 3x10 @ 25 lb rest 90s"].
        """

    /// Fixed lead-ins of the two per-request prompts. The rewrite one doubles as
    /// the prewarm prefix, so they live in one place.
    static let rewritePromptPrefix = "Convert this workout to notation lines:\n\n"
    static let generatePromptPrefix = "Extract the structured workout from this text:\n\n"

    /// Maps the model's `weightUnit` answer. Only a unit the model says was
    /// written counts; "unknown", "bodyweight", or anything unexpected falls
    /// back to the user's preferred unit, exactly like a bare number in notation.
    static func weightUnit(fromModel raw: String, default defaultUnit: WeightUnit) -> WeightUnit {
        switch raw.lowercased().trimmingCharacters(in: .whitespaces) {
        case "kg", "kgs", "kilo", "kilos", "kilogram", "kilograms": .kg
        case "lb", "lbs", "pound", "pounds": .lb
        default: defaultUnit
        }
    }

    // MARK: - Context budget

    /// Room left for the answer. A long session's structured output is a few
    /// hundred tokens; this leaves margin for ~15 exercises.
    static let outputTokenReserve = 1024
    /// Instructions + schema overhead per pass for the pre-26.4 estimate.
    /// `tokenCount` on the host model measured 625 + 142 (rewrite) and
    /// 936 + 659 (generate); rounded up for tokenizer differences.
    static let rewriteOverheadTokens = 900
    static let generateOverheadTokens = 1800

    /// The pre-26.4 estimate. Workout text is number- and symbol-dense:
    /// `tokenCount` measured ~2.5 characters per token (the usual 3.5 for
    /// English prose undercounts by ~40%), rounded up so the check errs toward
    /// skipping the model.
    static func estimatedTokens(_ text: String) -> Int {
        Int((Double(text.count) / 2.5).rounded(.up))
    }

    static func fitsContext(usedTokens: Int, contextSize: Int, outputReserve: Int = outputTokenReserve) -> Bool {
        usedTokens + outputReserve <= contextSize
    }

    #if canImport(FoundationModels)
    /// One model reading of the text.
    @available(iOS 26.0, *)
    private nonisolated enum Pass: CaseIterable {
        case rewrite
        case generate

        var instructions: String {
            self == .rewrite
                ? FoundationModelsWorkoutScanParser.rewriteInstructions
                : FoundationModelsWorkoutScanParser.instructions
        }

        var schema: GenerationSchema {
            self == .rewrite ? GeneratedNotation.generationSchema : GeneratedWorkout.generationSchema
        }

        var overheadTokens: Int {
            self == .rewrite
                ? FoundationModelsWorkoutScanParser.rewriteOverheadTokens
                : FoundationModelsWorkoutScanParser.generateOverheadTokens
        }

        func prompt(for text: String) -> String {
            (self == .rewrite
                ? FoundationModelsWorkoutScanParser.rewritePromptPrefix
                : FoundationModelsWorkoutScanParser.generatePromptPrefix) + text
        }
    }

    @available(iOS 26.0, *)
    private nonisolated enum PassOutcome {
        case draft(ParsedWorkoutDraft)
        /// The model answered, but nothing usable came out of it.
        case empty
        case failed(ModelFailure)
    }

    /// Runs both model readings unless a gate says the model can't help: not
    /// available, cooling down after a hard failure, unsupported locale, or text
    /// too long for the context window. Returns the candidates plus the issue to
    /// report when none came back.
    @available(iOS 26.0, *)
    private func modelCandidates(
        ocrText: String,
        referenceDate: Date,
        onStage: @Sendable (WorkoutParseStage) async -> Void
    ) async -> (candidates: [ParsedWorkoutDraft?], issue: ModelIssue?) {
        guard case .available = SystemLanguageModel.default.availability,
              await breaker.allowsRequests() else { return ([], .unavailable) }
        guard SystemLanguageModel.default.supportsLocale() else { return ([], .unsupportedLanguage) }

        // Two independent model readings: a rewrite into gym notation that the
        // deterministic parser then parses, and direct structured extraction.
        // The rewrite is the simpler task and its numbers pass through the
        // deterministic parser, so it gets tie priority (candidate order);
        // the arbiter scores both against the source text.
        var candidates: [ParsedWorkoutDraft?] = []
        var issues: [ModelIssue] = []
        for (index, pass) in Pass.allCases.enumerated() {
            if Task.isCancelled { return (candidates, nil) }
            guard await fitsContext(pass, text: ocrText) else {
                issues.append(.inputTooLong)
                continue
            }
            await onStage(.interpreting(pass: index + 1, of: Pass.allCases.count))
            switch await attempt(pass, ocrText: ocrText, referenceDate: referenceDate) {
            case .draft(let draft):
                candidates.append(draft)
            case .empty:
                break
            case .failed(.cancelled):
                return (candidates, nil)
            case .failed(let failure):
                if let issue = failure.issue { issues.append(issue) }
                if failure.tripsCircuitBreaker {
                    // Don't pay the same failure on the next pass, the next
                    // session of a batch paste, or the next parse for a while.
                    await breaker.trip()
                    return (candidates, candidates.isEmpty ? .unavailable : nil)
                }
            }
        }
        return (candidates, candidates.isEmpty ? issues.first : nil)
    }

    /// One attempt, plus a single fresh-session retry for transient failures.
    @available(iOS 26.0, *)
    private func attempt(_ pass: Pass, ocrText: String, referenceDate: Date) async -> PassOutcome {
        let outcome = await once(pass, ocrText: ocrText, referenceDate: referenceDate)
        if case .failed(let failure) = outcome, failure.isRetryable {
            return await once(pass, ocrText: ocrText, referenceDate: referenceDate)
        }
        return outcome
    }

    @available(iOS 26.0, *)
    private func once(_ pass: Pass, ocrText: String, referenceDate: Date) async -> PassOutcome {
        do {
            let draft: ParsedWorkoutDraft?
            switch pass {
            case .rewrite: draft = try await rewriteOnce(ocrText: ocrText, referenceDate: referenceDate)
            case .generate: draft = try await generateOnce(ocrText: ocrText, referenceDate: referenceDate)
            }
            return draft.map(PassOutcome.draft) ?? .empty
        } catch {
            // Every failure falls through to the deterministic parser via the
            // arbiter. A new session is required after a context overflow
            // (TN3193); each attempt builds its own session, so that holds.
            return .failed(Self.classify(error))
        }
    }

    /// Counts (iOS 26.4+) or estimates the prompt, instructions, and schema
    /// against the model's context window, leaving room for the answer. An
    /// overflow known up front costs nothing; one discovered by the call costs
    /// a full prefill. Splitting long pastes is the session segmenter's job.
    @available(iOS 26.0, *)
    private func fitsContext(_ pass: Pass, text: String) async -> Bool {
        let model = Self.transformationModel
        let prompt = pass.prompt(for: text)
        var used = Self.estimatedTokens(prompt) + pass.overheadTokens
        if #available(iOS 26.4, *) {
            do {
                used = try await model.tokenCount(for: prompt)
                    + model.tokenCount(for: Instructions(pass.instructions))
                    + model.tokenCount(for: pass.schema)
            } catch {
                // Keep the estimate; the call itself will report a real failure.
            }
        }
        // `contextSize` is back-deployed and reports 4096 before iOS 27.
        return Self.fitsContext(usedTokens: used, contextSize: model.contextSize)
    }

    @available(iOS 26.0, *)
    private func rewriteOnce(ocrText: String, referenceDate: Date) async throws -> ParsedWorkoutDraft? {
        let session = await PrewarmedRewriteSession.shared.take()
            ?? LanguageModelSession(model: Self.transformationModel, instructions: Self.rewriteInstructions)
        let response = try await session.respond(
            to: Pass.rewrite.prompt(for: ocrText),
            generating: GeneratedNotation.self,
            options: GenerationOptions(samplingMode: .greedy)
        )
        let notation = response.content
        let text = notation.lines.joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var draft = HandwrittenWorkoutParser.parseDetailed(
            text,
            referenceDate: referenceDate,
            defaultWeightUnit: defaultWeightUnit
        ).draft
        if draft.performedAt == nil {
            draft.performedAt = GeneratedWorkout.resolveDate(notation.dateText, referenceDate: referenceDate)
        }
        return draft.hasContent ? draft : nil
    }

    @available(iOS 26.0, *)
    private func generateOnce(ocrText: String, referenceDate: Date) async throws -> ParsedWorkoutDraft? {
        let session = LanguageModelSession(model: Self.transformationModel, instructions: Self.instructions)
        // Greedy decoding: extraction wants the single most likely reading, not
        // creative variety — and the same text should parse the same way twice.
        let response = try await session.respond(
            to: Pass.generate.prompt(for: ocrText),
            generating: GeneratedWorkout.self,
            options: GenerationOptions(samplingMode: .greedy)
        )
        let draft = response.content.draft(referenceDate: referenceDate, defaultWeightUnit: defaultWeightUnit)
        // The model occasionally returns nothing usable; the arbiter treats nil
        // as "deterministic parser wins".
        return draft.hasContent ? draft : nil
    }
    #endif

    /// Sorts a model error into a `ModelFailure`. iOS 27 throws the
    /// `LanguageModelError` family; iOS 26 throws `GenerationError`. Anything
    /// else — including the untyped "GenerationError -1 … no underlying assets
    /// for asset set com.apple.modelcatalog" seen when assets are missing — is
    /// recognized by its text or reported as `.unknown`.
    static func classify(_ error: any Error) -> ModelFailure {
        if error is CancellationError { return .cancelled }
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *) {
            if let error = error as? LanguageModelError {
                switch error {
                case .contextSizeExceeded: return .contextWindowExceeded
                case .rateLimited: return .rateLimited
                case .guardrailViolation: return .guardrailViolation
                case .refusal: return .refusal
                case .unsupportedLanguageOrLocale: return .unsupportedLanguage
                case .timeout: return .timeout
                case .unsupportedGenerationGuide, .unsupportedCapability, .unsupportedTranscriptContent:
                    return .unsupportedGuide
                @unknown default: return .unknown
                }
            }
            if error is SystemLanguageModel.Error { return .assetsUnavailable }
            if let error = error as? LanguageModelSession.Error, error == .concurrentRequests {
                return .concurrentRequests
            }
            if error is GeneratedContent.ParsingError { return .decodingFailure }
        }
        if #available(iOS 26.0, *), let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize: return .contextWindowExceeded
            case .assetsUnavailable: return .assetsUnavailable
            case .guardrailViolation: return .guardrailViolation
            case .unsupportedGuide: return .unsupportedGuide
            case .unsupportedLanguageOrLocale: return .unsupportedLanguage
            case .decodingFailure: return .decodingFailure
            case .rateLimited: return .rateLimited
            case .concurrentRequests: return .concurrentRequests
            case .refusal: return .refusal
            @unknown default: return .unknown
            }
        }
        #endif
        let description = "\(error) \((error as NSError).userInfo)".lowercased()
        if description.contains("modelcatalog") || description.contains("underlying assets") {
            return .assetsUnavailable
        }
        return .unknown
    }
}

/// Stops model calls for a cool-down after a hard failure (missing assets or an
/// unclassified framework error). Without it, a device mid-asset-update — or a
/// simulator whose availability check passes while every call throws — pays
/// failing model calls on every session of a batch paste and every preview.
/// One shared instance: the on-device model is one resource.
actor ModelCircuitBreaker {
    static let shared = ModelCircuitBreaker()

    private let coolDown: TimeInterval
    private let now: @Sendable () -> Date
    private var openUntil: Date?

    init(coolDown: TimeInterval = 10 * 60, now: @escaping @Sendable () -> Date = { Date() }) {
        self.coolDown = coolDown
        self.now = now
    }

    /// False while cooling down.
    func allowsRequests() -> Bool {
        guard let openUntil else { return true }
        if now() >= openUntil {
            self.openUntil = nil
            return true
        }
        return false
    }

    func trip() {
        openUntil = now().addingTimeInterval(coolDown)
    }

    func reset() {
        openUntil = nil
    }
}

/// Holds a parser's most recent `ModelIssue`. A class so the value-type parser
/// can record from its non-mutating `parse`; the mutex makes reads safe from
/// any isolation.
private nonisolated final class IssueReport: Sendable {
    private let state = Mutex<FoundationModelsWorkoutScanParser.ModelIssue?>(nil)

    var issue: FoundationModelsWorkoutScanParser.ModelIssue? {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}

#if canImport(FoundationModels)
/// The session `prewarm()` warmed, handed to the next rewrite pass while it is
/// fresh. Every attempt needs a clean session, so `take` removes it.
@available(iOS 26.0, *)
private actor PrewarmedRewriteSession {
    static let shared = PrewarmedRewriteSession()
    /// Past this the warm-up has likely been evicted; a new session is as good.
    private static let freshness: TimeInterval = 120

    private var session: LanguageModelSession?
    private var storedAt = Date.distantPast

    func store(_ session: LanguageModelSession) {
        self.session = session
        storedAt = Date()
    }

    func take() -> LanguageModelSession? {
        defer { session = nil }
        guard Date().timeIntervalSince(storedAt) < Self.freshness else { return nil }
        return session
    }
}

@available(iOS 26.0, *)
@Generable
nonisolated struct GeneratedNotation {
    @Guide(description: "The workout's date exactly as written, e.g. \"7/22\" or \"yesterday\". Empty if no date is mentioned.")
    var dateText: String
    @Guide(description: "One gym-notation line per distinct movement, e.g. \"Bench Press 3x8 @ 185 rest 90s\".")
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

    func draft(referenceDate: Date, defaultWeightUnit: WeightUnit = .lb) -> ParsedWorkoutDraft {
        let mapped = exercises.compactMap { $0.draft(defaultWeightUnit: defaultWeightUnit) }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedWorkoutDraft(
            performedAt: Self.resolveDate(dateText, referenceDate: referenceDate),
            title: cleanTitle.isEmpty ? "Scanned workout" : cleanTitle,
            exercises: mapped
        )
    }

    /// Calendar math stays out of the model: it reports the date *text* and code
    /// resolves it with exactly the deterministic parser's rules (local day,
    /// reference time of day, no future year-less dates). Weekdays, "last
    /// Tuesday", and "2 days ago" used to resolve to nil here and silently
    /// became "now".
    static func resolveDate(_ text: String, referenceDate: Date) -> Date? {
        HandwrittenWorkoutDateParser.resolveDateText(text, referenceDate: referenceDate)
    }
}

@available(iOS 26.0, *)
@Generable
nonisolated struct GeneratedExercise {
    /// Cap on expanded sets: room for a 60-minute EMOM (one set per minute),
    /// matching the `setCount` guide range.
    static let maxSetCount = 60

    // Name first: generation follows declaration order, and the name anchors the
    // numeric fields that follow it.
    @Guide(description: "The exercise name, e.g. \"Bench Press\" or \"Run\".")
    var name: String
    @Guide(description: "How many sets were performed. \"3x8\" and \"three sets of eight\" both mean 3. 1 if the text implies a single effort.", .range(1...60))
    var setCount: Int
    @Guide(description: "Reps per set; the lower bound for a range like \"8-12\". Nil when not stated.")
    var reps: Int?
    @Guide(description: "Weight in the unit the user wrote. Nil for bodyweight or unstated.")
    var weight: Double?
    @Guide(description: "Unit of the weight as written; \"unknown\" for a bare number.", .anyOf(["lb", "kg", "bodyweight", "unknown"]))
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
    /// plain code, mirroring the deterministic parser's `buildSets`. A unit the
    /// model didn't see written takes `defaultWeightUnit`, the user's preference.
    func draft(defaultWeightUnit: WeightUnit = .lb) -> ParsedExerciseDraft? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return nil }

        let unit = FoundationModelsWorkoutScanParser.weightUnit(fromModel: weightUnit, default: defaultWeightUnit)
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
        let count = min(max(setCount, variedCount, 1), Self.maxSetCount)

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
