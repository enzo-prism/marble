import CoreGraphics
import FoundationModels
import SwiftData
import XCTest
@testable import marble

/// The deterministic edges of the on-device parser: model-unit mapping, set
/// expansion caps, failure classification and retry policy, the context
/// budget, and the circuit breaker. None of these call the model.
@MainActor
final class FoundationModelsParserUnitTests: MarbleTestCase {
    typealias Parser = FoundationModelsWorkoutScanParser

    // MARK: - Weight units

    func testUnknownModelUnitTakesTheDefault() {
        XCTAssertEqual(Parser.weightUnit(fromModel: "unknown", default: .kg), .kg)
        XCTAssertEqual(Parser.weightUnit(fromModel: "unknown", default: .lb), .lb)
        XCTAssertEqual(Parser.weightUnit(fromModel: "bodyweight", default: .kg), .kg)
        XCTAssertEqual(Parser.weightUnit(fromModel: "", default: .kg), .kg)
    }

    func testWrittenModelUnitsStay() {
        XCTAssertEqual(Parser.weightUnit(fromModel: "lb", default: .kg), .lb)
        XCTAssertEqual(Parser.weightUnit(fromModel: "LB", default: .kg), .lb)
        XCTAssertEqual(Parser.weightUnit(fromModel: "kg", default: .lb), .kg)
        XCTAssertEqual(Parser.weightUnit(fromModel: " kilos ", default: .lb), .kg)
    }

    private func exercise(
        setCount: Int = 3,
        weight: Double? = 100,
        weightUnit: String
    ) -> GeneratedExercise {
        GeneratedExercise(
            name: "Squat",
            setCount: setCount,
            reps: 5,
            weight: weight,
            weightUnit: weightUnit,
            restSeconds: nil,
            durationSeconds: nil,
            distance: nil,
            distanceUnit: "none",
            perSetWeights: nil,
            perSetReps: nil
        )
    }

    func testGeneratedExerciseMapsUnknownUnitToDefault() throws {
        let draft = try XCTUnwrap(exercise(weightUnit: "unknown").draft(defaultWeightUnit: .kg))
        XCTAssertEqual(draft.sets.count, 3)
        XCTAssertTrue(draft.sets.allSatisfy { $0.weightUnit == .kg && $0.weight == 100 })
    }

    func testGeneratedExerciseKeepsExplicitUnit() throws {
        let pounds = try XCTUnwrap(exercise(weightUnit: "lb").draft(defaultWeightUnit: .kg))
        XCTAssertTrue(pounds.sets.allSatisfy { $0.weightUnit == .lb })
        let kilos = try XCTUnwrap(exercise(weightUnit: "kg").draft(defaultWeightUnit: .lb))
        XCTAssertTrue(kilos.sets.allSatisfy { $0.weightUnit == .kg })
    }

    func testGeneratedWorkoutThreadsDefaultUnit() {
        let workout = GeneratedWorkout(title: "", dateText: "", exercises: [exercise(weightUnit: "unknown")])
        let draft = workout.draft(referenceDate: now, defaultWeightUnit: .kg)
        XCTAssertEqual(draft.exercises.first?.sets.first?.weightUnit, .kg)
    }

    func testSetCountCapFitsAnHourLongEMOM() throws {
        let emom = try XCTUnwrap(exercise(setCount: 45, weight: nil, weightUnit: "bodyweight").draft())
        XCTAssertEqual(emom.sets.count, 45)
        let runaway = try XCTUnwrap(exercise(setCount: 500, weight: nil, weightUnit: "bodyweight").draft())
        XCTAssertEqual(runaway.sets.count, GeneratedExercise.maxSetCount)
    }

    // MARK: - Failure classification

    private typealias Failure = Parser.ModelFailure

    func testOnlyTransientFailuresRetry() {
        let retryable: [Failure] = [.guardrailViolation, .refusal, .rateLimited, .concurrentRequests]
        let final: [Failure] = [
            .contextWindowExceeded, .unsupportedLanguage, .unsupportedGuide, .assetsUnavailable,
            .decodingFailure, .timeout, .cancelled, .unknown,
        ]
        for failure in retryable { XCTAssertTrue(failure.isRetryable, "\(failure)") }
        for failure in final { XCTAssertFalse(failure.isRetryable, "\(failure)") }
    }

    func testOnlyHardFailuresTripTheBreaker() {
        XCTAssertTrue(Failure.assetsUnavailable.tripsCircuitBreaker)
        XCTAssertTrue(Failure.unknown.tripsCircuitBreaker)
        for failure: Failure in [.guardrailViolation, .refusal, .rateLimited, .contextWindowExceeded, .decodingFailure, .timeout, .cancelled] {
            XCTAssertFalse(failure.tripsCircuitBreaker, "\(failure)")
        }
    }

    func testFailuresMapToUserFacingIssues() {
        XCTAssertEqual(Failure.contextWindowExceeded.issue, .inputTooLong)
        XCTAssertEqual(Failure.unsupportedLanguage.issue, .unsupportedLanguage)
        XCTAssertEqual(Failure.assetsUnavailable.issue, .unavailable)
        XCTAssertEqual(Failure.refusal.issue, .failed)
        XCTAssertEqual(Failure.unknown.issue, .failed)
        XCTAssertNil(Failure.cancelled.issue)
    }

    func testClassifiesFrameworkErrors() {
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")
        XCTAssertEqual(Parser.classify(LanguageModelSession.GenerationError.assetsUnavailable(context)), .assetsUnavailable)
        XCTAssertEqual(Parser.classify(LanguageModelSession.GenerationError.exceededContextWindowSize(context)), .contextWindowExceeded)
        XCTAssertEqual(Parser.classify(LanguageModelSession.GenerationError.guardrailViolation(context)), .guardrailViolation)
        XCTAssertEqual(Parser.classify(LanguageModelSession.GenerationError.decodingFailure(context)), .decodingFailure)
        XCTAssertEqual(Parser.classify(LanguageModelSession.GenerationError.unsupportedLanguageOrLocale(context)), .unsupportedLanguage)
        XCTAssertEqual(Parser.classify(CancellationError()), .cancelled)
    }

    func testClassifiesMissingAssetsByDescription() {
        // What the simulator throws while reporting `.available`.
        let error = NSError(
            domain: "FoundationModels.LanguageModelSession.GenerationError",
            code: -1,
            userInfo: [NSDebugDescriptionErrorKey: "no underlying assets for asset set com.apple.modelcatalog"]
        )
        XCTAssertEqual(Parser.classify(error), .assetsUnavailable)
        XCTAssertEqual(Parser.classify(NSError(domain: "other", code: 7)), .unknown)
    }

    // MARK: - Context budget

    func testContextBudgetLeavesRoomForTheAnswer() {
        XCTAssertTrue(Parser.fitsContext(usedTokens: 3072, contextSize: 4096))
        XCTAssertFalse(Parser.fitsContext(usedTokens: 3073, contextSize: 4096))
        XCTAssertEqual(Parser.estimatedTokens(""), 0)
        XCTAssertEqual(Parser.estimatedTokens("12345"), 2)
        // A long week of notes can't fit the generate pass on a 4096 window.
        let longPaste = String(repeating: "Bench press 3x8 @ 185 rest 90s\n", count: 150)
        XCTAssertFalse(Parser.fitsContext(
            usedTokens: Parser.estimatedTokens(longPaste) + Parser.generateOverheadTokens,
            contextSize: 4096
        ))
    }

    // MARK: - Circuit breaker

    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_000_000)
    }

    func testBreakerCoolsDownThenReopens() async {
        let clock = Clock()
        let breaker = ModelCircuitBreaker(coolDown: 600, now: { clock.now })
        let initiallyAllowed = await breaker.allowsRequests()
        XCTAssertTrue(initiallyAllowed)

        await breaker.trip()
        clock.now += 599
        let duringCoolDown = await breaker.allowsRequests()
        XCTAssertFalse(duringCoolDown)

        clock.now += 1
        let afterCoolDown = await breaker.allowsRequests()
        XCTAssertTrue(afterCoolDown)
    }

    func testTrippedBreakerSkipsTheModelAndReportsUnavailable() async {
        let breaker = ModelCircuitBreaker()
        await breaker.trip()
        let parser = Parser(defaultWeightUnit: .kg, breaker: breaker)
        XCTAssertNil(parser.lastModelIssue)

        let draft = await parser.parse(ocrText: "Squat 5x5 @ 100", referenceDate: now)

        XCTAssertEqual(parser.lastModelIssue, .unavailable)
        XCTAssertEqual(draft.exercises.first?.sets.count, 5)
        XCTAssertEqual(draft.exercises.first?.sets.first?.weightUnit, .kg)
    }

    // MARK: - Scan gate

    private final class SpyParser: WorkoutScanParsing, @unchecked Sendable {
        var calls = 0
        func parse(ocrText: String, referenceDate: Date) async -> ParsedWorkoutDraft {
            calls += 1
            return HandwrittenWorkoutParser.parseDetailed(ocrText, referenceDate: referenceDate).draft
        }
    }

    private struct StubRecognizer: WorkoutTextRecognizing {
        let text: String
        func recognizeText(in image: CGImage) async throws -> String { text }
    }

    private func scan(_ text: String, unit: WeightUnit = .lb) async -> (WorkoutScanViewModel, SpyParser) {
        let spy = SpyParser()
        let viewModel = WorkoutScanViewModel(
            recognizer: StubRecognizer(text: text),
            parser: spy,
            defaultWeightUnit: unit
        )
        let image = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!.makeImage()!
        await viewModel.process(cgImage: image, imageData: Data(text.utf8), in: makeInMemoryContext())
        return (viewModel, spy)
    }

    func testScanTrustsCleanNotationWithoutTheModel() async {
        let (viewModel, spy) = await scan("Squat 5x5 @ 100\nBench 3x8 @ 80", unit: .kg)
        XCTAssertEqual(spy.calls, 0)
        XCTAssertEqual(viewModel.phase, .review)
        XCTAssertEqual(viewModel.draft.exercises.count, 2)
        XCTAssertEqual(viewModel.draft.exercises.first?.sets.first?.weightUnit, .kg)
    }

    func testScanEscalatesImplausibleAndProseText() async {
        let (_, implausible) = await scan("Bench 225x5x3")
        XCTAssertEqual(implausible.calls, 1)
        let (_, prose) = await scan("I did three sets of eight on bench at 185")
        XCTAssertEqual(prose.calls, 1)
    }
}
