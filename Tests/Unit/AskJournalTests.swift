import SwiftData
import UIKit
import XCTest
@testable import marble

#if canImport(FoundationModels)
import FoundationModels
#endif

/// The model-facing half of "Ask your journal", tested without the model
/// (the simulator's model reports available but every call fails): the
/// grounding validator, the tool ledger the model's tools call into, the
/// deterministic responder path, and the deadline that bounds a model turn.
@MainActor
final class AskJournalTests: MarbleTestCase {
    /// A fresh store per test (XCTest makes a new instance per test) holding
    /// Bench Press: 185 and 205 lb × 5 three days ago, 225 lb × 5 ten days ago.
    private lazy var context: ModelContext = {
        let context = makeInMemoryContext()
        let bench = Exercise(name: "Bench Press", category: .chest, metrics: .weightAndRepsRequired, defaultRestSeconds: 90)
        context.insert(bench)
        for (offset, weight) in [(-3, 185.0), (-3, 205.0), (-10, 225.0)] {
            let date = Self.stableCalendar.date(byAdding: .day, value: offset, to: now)!
            context.insert(SetEntry(exercise: bench, performedAt: date, weight: weight, reps: 5, restAfterSeconds: 90))
        }
        return context
    }()

    private func engine(_ unit: WeightUnit = .lb) -> JournalQueryEngine {
        JournalQueryEngine(context: context, unit: unit, now: now, calendar: Self.stableCalendar)
    }

    private func ledger(_ question: String) -> AskJournalLedger {
        let engine = engine()
        return AskJournalLedger(engine: engine, question: question, library: engine.library())
    }

    // MARK: - Validator

    private let facts = """
        Exercise: Bench Press
        Last logged: Jan 12, 2025 (3 days ago)
        Sets of Bench Press that day: 2
        Top set that day: 205 lb × 5
        """

    func testGroundedAnswerPasses() {
        let answer = "You last benched on Jan 12, 2025, with a top set of 205 lb × 5."
        XCTAssertEqual(AskAnswerValidator.validated(answer, facts: facts, unit: .lb), answer)
        XCTAssertEqual(
            AskAnswerValidator.validated("That was three days ago: 2 sets, topping out at 205 lb.", facts: facts, unit: .lb),
            "That was three days ago: 2 sets, topping out at 205 lb."
        )
    }

    func testUngroundedNumbersAreRejected() {
        XCTAssertNil(AskAnswerValidator.validated("Your top set was 210 lb × 5.", facts: facts, unit: .lb))
        XCTAssertNil(AskAnswerValidator.validated("You benched 93 kg.", facts: facts, unit: .lb))
        // A converted or more precise figure is not the fact either.
        XCTAssertNil(AskAnswerValidator.validated("You lifted 205.5 lb.", facts: facts, unit: .lb))
    }

    func testOnlyAGroundedSecondSentenceIsKept() {
        XCTAssertEqual(
            AskAnswerValidator.validated("You last benched 205 lb × 5 on Jan 12, 2025. That was 4 days ago.", facts: facts, unit: .lb),
            "You last benched 205 lb × 5 on Jan 12, 2025."
        )
        XCTAssertEqual(
            AskAnswerValidator.validated("You last benched on Jan 12, 2025. You did 2 sets. Then 9 more.", facts: facts, unit: .lb),
            "You last benched on Jan 12, 2025. You did 2 sets."
        )
        // A failed first sentence sinks the answer even if the second is fine.
        XCTAssertNil(AskAnswerValidator.validated("You benched 300 lb. You did 2 sets.", facts: facts, unit: .lb))
    }

    func testAdviceHealthAndHedgingAreBlocked() {
        let blocked = [
            "You benched 205 lb × 5. You should add weight next time.",
            "Great work — keep recovering well!",
            "You benched 205 lb, roughly your best.",
            "I recommend 2 sets of bench.",
            "Bench Press on Jan 12, 2025 burned calories.",
            "Your heart rate stayed steady."
        ]
        for answer in blocked {
            let result = AskAnswerValidator.validated(answer, facts: facts, unit: .lb)
            XCTAssertTrue(result == nil || !(result?.contains("should") ?? false), answer)
        }
        XCTAssertNil(AskAnswerValidator.validated("Keep recovering!", facts: facts, unit: .lb))
        XCTAssertNil(AskAnswerValidator.validated("Nice bench 💪", facts: facts, unit: .lb))
        XCTAssertNil(AskAnswerValidator.validated("I recommend 2 sets of bench.", facts: facts, unit: .lb))
        XCTAssertNil(AskAnswerValidator.validated("Your heart rate stayed steady.", facts: facts, unit: .lb))
    }

    func testCleaningAndSentenceSplitting() {
        XCTAssertEqual(AskAnswerValidator.validated("\"**205 lb × 5** on Jan 12, 2025.\"", facts: facts, unit: .lb), "205 lb × 5 on Jan 12, 2025.")
        XCTAssertEqual(AskAnswerValidator.splitSentences("Your best is 14.8s. Nice! Done"), ["Your best is 14.8s.", "Nice!", "Done"])
        XCTAssertNil(AskAnswerValidator.validated("   ", facts: facts, unit: .lb))
        XCTAssertNil(AskAnswerValidator.validated("You benched.", facts: "", unit: .lb))
    }

    func testMetricVolumeShorthandIsGrounded() {
        let volumeFacts = "Volume (weight × reps): 12.3t"
        XCTAssertNotNil(AskAnswerValidator.validated("You moved 12.3t this week.", facts: volumeFacts, unit: .kg))
        XCTAssertNil(AskAnswerValidator.validated("You moved 12.4t this week.", facts: volumeFacts, unit: .kg))
    }

    // MARK: - Ledger (what the model's tools call)

    func testLedgerRecordsFactsAndCardsForEachToolCall() throws {
        let ledger = ledger("When did I last bench?")
        let output = try ledger.lastTime(exercise: "bench press", minimumWeight: 0, unit: "")
        XCTAssertTrue(output.contains("Top set that day: 205 lb × 5"), output)
        XCTAssertEqual(ledger.results.count, 1)
        XCTAssertEqual(ledger.cards.count, 1)
        XCTAssertEqual(ledger.facts, output)
        // The engine's own facts ground the engine's own sentence.
        XCTAssertNotNil(AskAnswerValidator.validated(ledger.results[0].sentence, facts: ledger.facts, unit: .lb))
    }

    func testLedgerBoundsToolCalls() throws {
        let ledger = ledger("How many sets this week?")
        for _ in 0..<AskJournalLedger.maximumToolCalls {
            _ = try ledger.totals(period: "this week", exercise: "")
        }
        XCTAssertThrowsError(try ledger.totals(period: "this week", exercise: "")) { error in
            XCTAssertEqual(error as? AskJournalLedger.ToolError, .callLimitReached)
        }
        XCTAssertEqual(ledger.results.count, AskJournalLedger.maximumToolCalls)
    }

    func testQuestionPeriodOutranksTheModelsPeriod() throws {
        let stated = ledger("How many sets this week?")
        _ = try stated.totals(period: "last month", exercise: "")
        XCTAssertTrue(stated.facts.contains("Period: this week"), stated.facts)

        let unstated = ledger("How many sets have I done?")
        _ = try unstated.totals(period: "last 7 days", exercise: "")
        XCTAssertTrue(unstated.facts.contains("Period: in the last 7 days"), unstated.facts)

        let gibberish = ledger("How many sets have I done?")
        _ = try gibberish.totals(period: "whenever", exercise: "")
        XCTAssertTrue(gibberish.facts.contains("Period: all time"), gibberish.facts)
    }

    func testLedgerResolvesExercisesFromTheModelOrTheQuestion() throws {
        let fromQuestion = ledger("heaviest bench?")
        _ = try fromQuestion.best(exercise: "", measure: .heaviest, period: "all time")
        XCTAssertEqual(fromQuestion.cards.first?.value, "225 lb × 5")

        let unknown = ledger("When did I last do zumba?")
        let output = try unknown.lastTime(exercise: "zumba", minimumWeight: 0, unit: "")
        XCTAssertTrue(output.hasPrefix("No exercise named “zumba” is in the journal."), output)
        XCTAssertTrue(output.contains("Bench Press"))
        XCTAssertTrue(unknown.results.isEmpty)
        XCTAssertTrue(unknown.cards.isEmpty)
    }

    func testLedgerKeepsTheQuestionsThresholdUnitAndFallsBackToPreference() throws {
        let stated = ledger("last time I benched 90 kg")
        let output = try stated.lastTime(exercise: "bench", minimumWeight: 90, unit: "")
        XCTAssertTrue(output.contains("Filter: sets at or above 90 kg"), output)

        let inferred = ledger("last heavy bench")
        let inferredOutput = try inferred.lastTime(exercise: "bench", minimumWeight: 200, unit: "")
        XCTAssertTrue(inferredOutput.contains("Filter: sets at or above 200 lb"), inferredOutput)
        XCTAssertEqual(AskJournalLedger.weightUnit("kilograms"), .kg)
        XCTAssertEqual(AskJournalLedger.weightUnit("lbs"), .lb)
        XCTAssertNil(AskJournalLedger.weightUnit(""))
    }

    func testWorkoutsToolListsAPeriodOrFindsTheLatestMatch() throws {
        let set = try XCTUnwrap(context.fetch(FetchDescriptor<SetEntry>()).first)
        let start = Self.stableCalendar.date(byAdding: .day, value: -2, to: now)!
        context.insert(WorkoutSession(title: "Push", startedAt: start, endedAt: start.addingTimeInterval(1800), entries: [set]))

        let listing = ledger("What did I do?")
        _ = try listing.workouts(matching: "", period: "this week")
        XCTAssertTrue(listing.facts.contains("Recorded workouts: 1"), listing.facts)

        let latest = ledger("Last push day?")
        _ = try latest.workouts(matching: "push", period: "all time")
        XCTAssertTrue(latest.facts.contains("Most recent workout matching “push”: Push"), latest.facts)
    }

    #if canImport(FoundationModels)
    func testToolsForwardTheirArgumentsToTheLedger() async throws {
        let ledger = ledger("When did I last bench?")
        let output = try await AskLastTimeTool(ledger: ledger).call(arguments: .init(exercise: "bench", minimumWeight: 0, weightUnit: ""))
        XCTAssertTrue(output.contains("Exercise: Bench Press"), output)
        let best = try await AskBestTool(ledger: ledger).call(arguments: .init(exercise: "bench", measure: .heaviest, period: "all time"))
        XCTAssertTrue(best.contains("Heaviest set: 225 lb × 5"), best)
        XCTAssertEqual(ledger.callCount, 2)
        XCTAssertEqual(AskMeasure.best.journalMeasure, .automatic)
    }
    #endif

    // MARK: - Responder

    func testDeterministicAnswerUsesTheTemplateAndHonestFooter() async {
        let answer = await AskJournalResponder.answer("When did I last bench?", engine: engine(), allowModel: false)
        XCTAssertEqual(answer.kind, .answered)
        XCTAssertEqual(answer.source, .template)
        XCTAssertEqual(answer.sentence, "You last did Bench Press on Jan 12, 2025 (3 days ago): 2 sets, top set 205 lb × 5.")
        XCTAssertEqual(answer.cards.count, 1)
        XCTAssertEqual(answer.footer, "Answered on this device from your journal.")
    }

    func testUnanswerableQuestionsExplainWhatMarbleCanAnswer() async {
        let answer = await AskJournalResponder.answer("Tell me a joke", engine: engine(), allowModel: false)
        XCTAssertEqual(answer.kind, .unanswerable)
        XCTAssertEqual(answer.sentence, AskJournalAnswer.capabilities)
        XCTAssertTrue(answer.cards.isEmpty)
        let blank = await AskJournalResponder.answer("   ", engine: engine(), allowModel: false)
        XCTAssertEqual(blank.kind, .unanswerable)
    }

    func testAppleIntelligenceFooterOnlyWhenTheModelWrote() {
        let written = AskJournalAnswer(question: "q", sentence: "s", cards: [], source: .appleIntelligence, kind: .answered)
        XCTAssertEqual(written.footer, "Answered on this device from your journal. Written with Apple Intelligence.")
    }

    func testModelIsNeverUsedInTestHostsAndTheToolbarSymbolsExist() {
        XCTAssertFalse(AskJournalModel.isAvailable)
        XCTAssertEqual(AskJournalModel.toolbarSymbol, "text.magnifyingglass")
        XCTAssertNotNil(UIImage(systemName: "apple.intelligence"))
        XCTAssertNotNil(UIImage(systemName: "text.magnifyingglass"))
        XCTAssertTrue(AskJournalModel.instructions(today: now, calendar: Self.stableCalendar).contains("Today's date is 2025-01-15."))
    }

    // MARK: - Deadline

    func testDeadlineReturnsTheResultWhenInTime() async throws {
        let value = try await AskDeadline.run(.seconds(5)) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testDeadlineTimesOutEvenIfTheOperationIgnoresCancellation() async {
        let started = ContinuousClock.now
        do {
            _ = try await AskDeadline.run(.milliseconds(100)) { () async throws -> Int in
                // Deliberately not cancellable.
                let end = ContinuousClock.now.advanced(by: .seconds(3))
                while ContinuousClock.now < end { await Task.yield() }
                return 1
            }
            XCTFail("Expected a timeout")
        } catch {
            XCTAssertTrue(error is AskDeadline.TimedOut, "\(error)")
        }
        XCTAssertLessThan(started.duration(to: .now), .seconds(2))
    }

    func testDeadlinePropagatesErrorsAndCancellation() async {
        struct Boom: Error {}
        do {
            _ = try await AskDeadline.run(.seconds(5)) { () async throws -> Int in throw Boom() }
            XCTFail("Expected an error")
        } catch {
            XCTAssertTrue(error is Boom)
        }

        let task = Task {
            try await AskDeadline.run(.seconds(5)) { () async throws -> Int in
                try await Task.sleep(for: .seconds(5))
                return 1
            }
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
    }
}
