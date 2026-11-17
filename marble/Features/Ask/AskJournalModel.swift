import Foundation
import Synchronization

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Answer

/// What the Ask sheet renders. Cards always come from engine output; the
/// sentence is either the model's (validated) or the engine's template.
nonisolated struct AskJournalAnswer: Equatable, Sendable {
    nonisolated enum Source: Equatable, Sendable {
        case appleIntelligence
        case template
    }

    nonisolated enum Kind: Equatable, Sendable {
        case answered
        /// Nothing Marble understands was asked; the sheet lists what it can answer.
        case unanswerable
    }

    let question: String
    let sentence: String
    let cards: [JournalCard]
    let source: Source
    let kind: Kind

    /// Honest provenance, mirroring `MonthlyReportSheet`: the reader can't
    /// tell model prose from the template, so the footer says who wrote it.
    var footer: String {
        switch source {
        case .appleIntelligence:
            return "Answered on this device from your journal. Written with Apple Intelligence."
        case .template:
            return "Answered on this device from your journal."
        }
    }

    static let capabilities = "Marble can answer questions about your own log: when you last did an exercise, your heaviest or best set, how many sets or workouts in a period, and your recent workouts."
}

// MARK: - Responder

/// Answers one question: the on-device model when it is usable (it picks the
/// tools and phrases the result), the deterministic matcher otherwise — and
/// whenever the model fails, times out, or writes something the validator
/// rejects. No network, no Private Cloud Compute, nothing persisted.
@MainActor
enum AskJournalResponder {
    static let maximumQuestionLength = 240

    static func answer(
        _ question: String,
        engine: JournalQueryEngine,
        allowModel: Bool = AskJournalModel.isAvailable
    ) async -> AskJournalAnswer {
        let trimmed = String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumQuestionLength))
        guard !trimmed.isEmpty else { return unanswerable(trimmed) }
        let library = engine.library()
        let fallbackQuery = engine.matcher(library: library).query(for: trimmed)

        #if canImport(FoundationModels)
        if allowModel, await ModelCircuitBreaker.shared.allowsRequests() {
            let ledger = AskJournalLedger(engine: engine, question: trimmed, library: library)
            if let raw = await AskJournalModel.respond(to: trimmed, ledger: ledger),
               !ledger.results.isEmpty,
               let sentence = AskAnswerValidator.validated(raw, facts: ledger.facts, unit: engine.unit) {
                return AskJournalAnswer(
                    question: trimmed,
                    sentence: sentence,
                    cards: ledger.cards,
                    source: .appleIntelligence,
                    kind: .answered
                )
            }
            // The model's wording was rejected, but if its tools found
            // something the matcher can't reach, keep that answer — in the
            // engine's own words.
            if fallbackQuery == nil, let result = ledger.results.first(where: \.found) ?? ledger.results.first {
                return AskJournalAnswer(question: trimmed, sentence: result.sentence, cards: result.cards, source: .template, kind: .answered)
            }
        }
        #endif

        return deterministicAnswer(trimmed, query: fallbackQuery, engine: engine)
    }

    static func deterministicAnswer(_ question: String, query: JournalQuery?, engine: JournalQueryEngine) -> AskJournalAnswer {
        guard let query else { return unanswerable(question) }
        let result = engine.run(query)
        return AskJournalAnswer(question: question, sentence: result.sentence, cards: result.cards, source: .template, kind: .answered)
    }

    static func unanswerable(_ question: String) -> AskJournalAnswer {
        AskJournalAnswer(question: question, sentence: AskJournalAnswer.capabilities, cards: [], source: .template, kind: .unanswerable)
    }
}

// MARK: - Ledger

/// The model's only window onto the journal. Each tool call runs one engine
/// query here (on the main actor, where the model context lives), and the
/// ledger keeps both the text the model read — the grounding facts — and the
/// structured cards the sheet renders. Bounded: past `maximumToolCalls` the
/// tools refuse, which ends the turn and drops to the deterministic path.
@MainActor
final class AskJournalLedger {
    static let maximumToolCalls = 4

    nonisolated enum ToolError: Error, Equatable {
        case callLimitReached
    }

    let engine: JournalQueryEngine
    let question: String
    let library: [ExerciseMatcher.Candidate]
    let reading: JournalQuestionReading

    private(set) var results: [JournalResult] = []
    private(set) var outputs: [String] = []
    private(set) var callCount = 0

    init(engine: JournalQueryEngine, question: String, library: [ExerciseMatcher.Candidate]) {
        self.engine = engine
        self.question = question
        self.library = library
        self.reading = engine.matcher(library: library).reading(of: question)
    }

    /// Everything the tools returned, for `AskAnswerValidator`.
    var facts: String { outputs.joined(separator: "\n") }

    /// Cards from every tool result, de-duplicated, at most six.
    var cards: [JournalCard] {
        var seen = Set<String>()
        var cards: [JournalCard] = []
        for card in results.flatMap(\.cards) where seen.insert(card.id).inserted {
            cards.append(card)
        }
        return Array(cards.prefix(6))
    }

    func lastTime(exercise name: String, minimumWeight: Double, unit unitText: String) throws -> String {
        try countCall()
        guard let exercise = resolveExercise(name) else { return notFound(name) }
        var threshold: WeightThreshold?
        if minimumWeight > 0 {
            if let stated = reading.threshold, abs(stated.value - minimumWeight) < 0.001 {
                threshold = stated
            } else {
                threshold = WeightThreshold(value: minimumWeight, unit: Self.weightUnit(unitText) ?? engine.unit)
            }
        }
        return record(engine.run(.lastPerformed(exerciseID: exercise.id, atLeast: threshold)))
    }

    func best(exercise name: String, measure: JournalBestMeasure, period: String) throws -> String {
        try countCall()
        guard let exercise = resolveExercise(name) else { return notFound(name) }
        return record(engine.run(.best(
            exerciseID: exercise.id,
            measure: measure,
            period: resolvePeriod(period, default: .allTime),
            distanceMeters: reading.distanceMeters
        )))
    }

    func totals(period: String, exercise name: String) throws -> String {
        try countCall()
        var exerciseID: UUID?
        if !name.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let exercise = resolveExercise(name) else { return notFound(name) }
            exerciseID = exercise.id
        }
        return record(engine.run(.totals(period: resolvePeriod(period, default: .allTime), exerciseID: exerciseID)))
    }

    func workouts(matching term: String, period: String) throws -> String {
        try countCall()
        let resolved = resolvePeriod(period, default: .allTime)
        if resolved != .allTime {
            return record(engine.run(.sessions(period: resolved)))
        }
        return record(engine.run(.recentSession(matching: term.trimmingCharacters(in: .whitespacesAndNewlines))))
    }

    // MARK: Helpers

    private func countCall() throws {
        callCount += 1
        if callCount > Self.maximumToolCalls { throw ToolError.callLimitReached }
    }

    private func record(_ result: JournalResult) -> String {
        results.append(result)
        outputs.append(result.factText)
        return result.factText
    }

    private func notFound(_ name: String) -> String {
        let known = library.prefix(8).map(\.name).joined(separator: ", ")
        let output = known.isEmpty
            ? "No exercise named “\(name)” is in the journal, and the library is empty."
            : "No exercise named “\(name)” is in the journal. Exercises in the library include: \(known)."
        outputs.append(output)
        return output
    }

    /// A confident library match for the model's name wins; otherwise the
    /// exercise the question itself names; otherwise the model's best guess.
    func resolveExercise(_ name: String) -> ExerciseMatcher.Candidate? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let direct = ExerciseMatcher(candidates: library).bestMatch(for: trimmed), direct.confidence >= .strong {
            return direct.candidate
        }
        if let stated = reading.exercise { return stated }
        return trimmed.isEmpty ? nil : engine.resolveExercise(named: trimmed, library: library)
    }

    /// A single time phrase in the question is the authority (the model may
    /// mis-state it); otherwise the model's phrase is parsed the same way.
    func resolvePeriod(_ modelText: String, default fallback: JournalPeriod) -> JournalPeriod {
        if let stated = reading.solePeriod { return stated }
        let text = modelText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = JournalTimeParser.period(in: text, now: engine.now, calendar: engine.calendar) { return parsed }
        return fallback
    }

    static func weightUnit(_ text: String) -> WeightUnit? {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespaces)
        if lowered.hasPrefix("k") { return .kg }
        if lowered.hasPrefix("lb") || lowered.hasPrefix("pound") { return .lb }
        return nil
    }
}

// MARK: - Model

/// Availability, instructions, and the bounded model call.
enum AskJournalModel {
    static let timeLimit: Duration = .seconds(15)
    static let maximumResponseTokens = 160

    /// The model is used only on a device where Apple Intelligence is ready
    /// for the current language, never in test hosts (the simulator reports
    /// "available" while every call fails, and tests must be deterministic).
    static var isAvailable: Bool {
        guard !TestHooks.isXCTestProcess, !TestHooks.isUITesting else { return false }
        return TrainingInsights.isModelAvailable
    }

    /// History's toolbar glyph: Apple Intelligence's mark only when the model
    /// will actually write the answer.
    static var toolbarSymbol: String { isAvailable ? "apple.intelligence" : "text.magnifyingglass" }

    static func instructions(today: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: today)
        let iso = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return """
            You answer questions about the user's own strength-training journal in the Marble app. \
            Today's date is \(iso). Always call a tool to look the answer up; never answer from memory. \
            Call the one most relevant tool, and call another only if the first cannot answer. \
            Then reply in one or two short sentences that say what the tool output shows. \
            Use only numbers, dates, units and names exactly as they appear in the tool output — never \
            calculate, convert, round, or estimate. If the tool output says nothing was found, say so plainly. \
            Describe only: never give advice or recommendations, never say "should", and never mention \
            injury, pain, recovery, sleep, health, diet, nutrition, calories, or bodyweight. No emoji.
            """
    }

    #if canImport(FoundationModels)
    /// The model's raw reply, or nil on any failure, timeout, or cancellation.
    static func respond(to question: String, ledger: AskJournalLedger) async -> String? {
        let tools: [any Tool] = [
            AskLastTimeTool(ledger: ledger),
            AskBestTool(ledger: ledger),
            AskTotalsTool(ledger: ledger),
            AskWorkoutsTool(ledger: ledger)
        ]
        let instructions = instructions(today: ledger.engine.now, calendar: ledger.engine.calendar)
        let tokens = maximumResponseTokens
        do {
            return try await AskDeadline.run(timeLimit) {
                let session = LanguageModelSession(tools: tools, instructions: instructions)
                // Greedy: the same question over the same journal reads the
                // same way every time.
                let response = try await session.respond(
                    to: question,
                    options: GenerationOptions(sampling: .greedy, maximumResponseTokens: tokens)
                )
                return response.content
            }
        } catch {
            await recordFailure(error)
            return nil
        }
    }

    /// Hard model failures cool the shared breaker down (the scan parser and
    /// Ask share one on-device model); our own limits never do.
    private static func recordFailure(_ error: any Error) async {
        if error is AskDeadline.TimedOut || error is CancellationError { return }
        if error is LanguageModelSession.ToolCallError { return }
        let failure = FoundationModelsWorkoutScanParser.classify(error)
        if failure == .rateLimited {
            await ModelCircuitBreaker.shared.postpone(until: FoundationModelsWorkoutScanParser.retryDateAfterRateLimit(error))
        } else if failure.tripsCircuitBreaker {
            await ModelCircuitBreaker.shared.trip()
        }
    }
    #endif
}

// MARK: - Deadline

/// Races an operation against a time limit and the caller's cancellation,
/// returning as soon as either wins — even if the operation itself ignores
/// cancellation (it is cancelled, and its late result is discarded).
nonisolated enum AskDeadline {
    struct TimedOut: Error, Equatable {}

    static func run<T: Sendable>(
        _ limit: Duration,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let gate = DeadlineGate<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                gate.add(Task {
                    do { gate.finish(.success(try await operation())) } catch { gate.finish(.failure(error)) }
                })
                gate.add(Task {
                    do { try await Task.sleep(for: limit) } catch { return }
                    gate.finish(.failure(TimedOut()))
                })
            }
        } onCancel: {
            gate.finish(.failure(CancellationError()))
        }
    }
}

/// Resume-exactly-once bookkeeping for `AskDeadline`.
nonisolated final class DeadlineGate<T: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<T, any Error>?
        var pending: Result<T, any Error>?
        var finished = false
        var tasks: [Task<Void, Never>] = []
    }

    private let state = Mutex(State())

    func install(_ continuation: CheckedContinuation<T, any Error>) {
        let pending: Result<T, any Error>? = state.withLock { state in
            if let pending = state.pending {
                state.pending = nil
                return pending
            }
            state.continuation = continuation
            return nil
        }
        if let pending { continuation.resume(with: pending) }
    }

    func add(_ task: Task<Void, Never>) {
        let finished = state.withLock { state in
            if !state.finished { state.tasks.append(task) }
            return state.finished
        }
        if finished { task.cancel() }
    }

    func finish(_ result: Result<T, any Error>) {
        let taken: (CheckedContinuation<T, any Error>?, [Task<Void, Never>])? = state.withLock { state in
            guard !state.finished else { return nil }
            state.finished = true
            let continuation = state.continuation
            if continuation == nil { state.pending = result }
            let tasks = state.tasks
            state.continuation = nil
            state.tasks = []
            return (continuation, tasks)
        }
        guard let taken else { return }
        taken.1.forEach { $0.cancel() }
        taken.0?.resume(with: result)
    }
}

// MARK: - Tools

#if canImport(FoundationModels)
@Generable
nonisolated enum AskMeasure {
    case heaviest
    case mostReps
    case fastest
    case longest
    case best

    var journalMeasure: JournalBestMeasure {
        switch self {
        case .heaviest: .heaviest
        case .mostReps: .mostReps
        case .fastest: .fastest
        case .longest: .longest
        case .best: .automatic
        }
    }
}

nonisolated struct AskLastTimeTool: Tool {
    let ledger: AskJournalLedger
    let name = "findLastTime"
    let description = "Finds when the user last logged an exercise, optionally only sets at or above a weight."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "The exercise as the user wrote it, e.g. \"bench press\" or \"squat\".")
        var exercise: String
        @Guide(description: "The minimum weight the user asked about (one dumbbell for dumbbell exercises), or 0 when they gave none.")
        var minimumWeight: Double
        @Guide(description: "Unit of minimumWeight: \"lb\" or \"kg\". Empty when there is no weight.")
        var weightUnit: String
    }

    @concurrent func call(arguments: Arguments) async throws -> String {
        let exercise = arguments.exercise
        let weight = arguments.minimumWeight
        let unit = arguments.weightUnit
        return try await ledger.lastTime(exercise: exercise, minimumWeight: weight, unit: unit)
    }
}

nonisolated struct AskBestTool: Tool {
    let ledger: AskJournalLedger
    let name = "findBest"
    let description = "Finds the user's best set of an exercise: heaviest weight, most reps, fastest time, or longest time."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "The exercise as the user wrote it, e.g. \"deadlift\".")
        var exercise: String
        @Guide(description: "Which best: heaviest, mostReps, fastest, longest, or best when the user didn't say.")
        var measure: AskMeasure
        @Guide(description: "Time period such as \"all time\", \"this month\", \"last 30 days\", or \"2026-11-01 to 2026-11-10\".")
        var period: String
    }

    @concurrent func call(arguments: Arguments) async throws -> String {
        let exercise = arguments.exercise
        let measure = arguments.measure.journalMeasure
        let period = arguments.period
        return try await ledger.best(exercise: exercise, measure: measure, period: period)
    }
}

nonisolated struct AskTotalsTool: Tool {
    let ledger: AskJournalLedger
    let name = "countTraining"
    let description = "Counts sets, training days, recorded workouts and total volume in a period, for all exercises or one exercise."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "Time period such as \"this week\", \"last month\", \"last 7 days\", \"all time\", or \"2026-11-01 to 2026-11-10\".")
        var period: String
        @Guide(description: "One exercise to count, or empty for all exercises.")
        var exercise: String
    }

    @concurrent func call(arguments: Arguments) async throws -> String {
        let period = arguments.period
        let exercise = arguments.exercise
        return try await ledger.totals(period: period, exercise: exercise)
    }
}

nonisolated struct AskWorkoutsTool: Tool {
    let ledger: AskJournalLedger
    let name = "findWorkouts"
    let description = "Finds the most recent recorded workout matching a name or exercise, or lists the workouts in a period."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "Workout name or exercise to match, e.g. \"leg day\". Empty for any workout.")
        var matching: String
        @Guide(description: "Time period to list, e.g. \"last week\". Use \"all time\" for the most recent matching workout.")
        var period: String
    }

    @concurrent func call(arguments: Arguments) async throws -> String {
        let matching = arguments.matching
        let period = arguments.period
        return try await ledger.workouts(matching: matching, period: period)
    }
}
#endif
