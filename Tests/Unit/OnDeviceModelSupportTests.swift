import CoreGraphics
import SwiftData
import XCTest
@testable import marble

/// The testable edges of the Apple Intelligence improvements: the plain-text
/// rewrite format, the context-derived budget, model-version diagnostics,
/// page-image preparation, source excerpts, reading feedback, and the
/// availability copy. None of these call the model.
@MainActor
final class OnDeviceModelSupportTests: MarbleTestCase {
    typealias Parser = FoundationModelsWorkoutScanParser

    // MARK: - Plain-text rewrite output

    func testParsesBareNotationLinesAndDate() {
        let output = ModelNotationOutput.parse("""
            Date: 1/10/25
            Bench Press 3x8 @ 185
            Squat 5x5 @ 225 rest 90s
            """)
        XCTAssertEqual(output.dateText, "1/10/25")
        XCTAssertEqual(output.lines, ["Bench Press 3x8 @ 185", "Squat 5x5 @ 225 rest 90s"])
    }

    func testStripsBulletsNumberingFencesAndEmphasis() {
        let output = ModelNotationOutput.parse("""
            ```text
            - Bench Press 3x8 @ 185
            * Row 3x10
            • Plank 3x45s
            1. Squat 5x5 @ 225
            2) Deadlift 1x5 @ 315
            (3) Pushups 3x10
            **Run 5km 25:00**
            > `Curl 3x12`
            "Dips 3x8"
            ```
            """)
        XCTAssertEqual(output.lines, [
            "Bench Press 3x8 @ 185", "Row 3x10", "Plank 3x45s", "Squat 5x5 @ 225",
            "Deadlift 1x5 @ 315", "Pushups 3x10", "Run 5km 25:00", "Curl 3x12", "Dips 3x8",
        ])
        XCTAssertEqual(output.dateText, "")
    }

    func testDropsChatterButKeepsLookalikeExerciseNames() {
        let output = ModelNotationOutput.parse("""
            Sure, here is the workout in notation:
            Here's what I found.
            Notation lines:
            Bench 3x8 @ 185
            Surestep Lunge 3x10
            Note: I dropped the intensity percentages.
            ---
            Hope this helps!
            """)
        XCTAssertEqual(output.lines, ["Bench 3x8 @ 185", "Surestep Lunge 3x10"])
    }

    func testLeadingSetCountIsNotMistakenForNumbering() {
        XCTAssertEqual(ModelNotationOutput.parse("5x5 Squat @ 225").lines, ["5x5 Squat @ 225"])
        XCTAssertEqual(ModelNotationOutput.parse("3 sets of 8 bench").lines, ["3 sets of 8 bench"])
    }

    func testDatePlaceholdersAndCommentaryAreNotDates() {
        XCTAssertEqual(ModelNotationOutput.parse("Date: none\nBench 3x8").dateText, "")
        XCTAssertEqual(ModelNotationOutput.parse("Date: N/A\nBench 3x8").dateText, "")
        XCTAssertEqual(ModelNotationOutput.parse("Date: \"yesterday\"\nBench 3x8").dateText, "yesterday")
        XCTAssertEqual(ModelNotationOutput.parse("Date: 9/4/26 (as written)\nBench 3x8").dateText, "9/4/26")
        XCTAssertEqual(ModelNotationOutput.parse("- Date: 7/22.\nBench 3x8").dateText, "7/22")
        // Only the first date line counts; a second one never becomes a line.
        let twice = ModelNotationOutput.parse("Date: 7/22\nBench 3x8\nDate: 7/23")
        XCTAssertEqual(twice.dateText, "7/22")
        XCTAssertEqual(twice.lines, ["Bench 3x8"])
    }

    func testRunawayAnswersAreBounded() {
        let answer = (1...200).map { "Bench \($0)x1" }.joined(separator: "\n")
        XCTAssertEqual(ModelNotationOutput.parse(answer).lines.count, ModelNotationOutput.maximumLines)
    }

    func testStreamingShowsOnlyFinishedLines() {
        XCTAssertEqual(ModelNotationOutput.completedLines(in: "Date: 1/10/25\nBench 3x"), [])
        XCTAssertEqual(ModelNotationOutput.completedLines(in: "Bench 3x8 @ 185\nSqu"), ["Bench 3x8 @ 185"])
        XCTAssertEqual(ModelNotationOutput.completedLines(in: ""), [])
    }

    /// Streaming must not change the result: whatever prefix the UI showed,
    /// the draft comes from the complete answer, and the finished lines of
    /// every snapshot are a prefix of the final lines.
    func testStreamedSnapshotsConvergeOnTheNonStreamedReading() throws {
        let answer = "Date: 1/10/25\n- Bench Press 3x8 @ 185\nPlank 3x45s\nRun 5km 25:00"
        let final = ModelNotationOutput.parse(answer).lines
        var previous: [String] = []
        for end in answer.indices {
            let shown = ModelNotationOutput.completedLines(in: String(answer[...end]))
            XCTAssertEqual(Array(final.prefix(shown.count)), shown)
            XCTAssertGreaterThanOrEqual(shown.count, previous.count)
            previous = shown
        }
        XCTAssertEqual(ModelNotationOutput.completedLines(in: answer + "\n"), final)

        let source = "Jan 10th: bench 3 sets of 8 at 185, planks 3 x 45 seconds, 5k run in 25 min"
        let streamed = try XCTUnwrap(Parser.rewriteDraft(
            fromModelText: answer, source: source, referenceDate: now, defaultWeightUnit: .lb
        ))
        XCTAssertEqual(streamed.exercises.map(\.name).count, 3)
    }

    func testRewriteDraftReadsNotationAndGroundsTheDate() throws {
        let source = """
            1/10/25

            Straight Leg Speed Bounds (2 sets)

            Resistance Rope Sprint 2 sets , 50m each
            """
        let answer = """
            Here is the workout:
            Date: 1/10/25
            1. Straight Leg Speed Bounds 2 sets
            2. Resistance Rope Sprint 2x50m
            """
        let draft = try XCTUnwrap(Parser.rewriteDraft(
            fromModelText: answer, source: source, referenceDate: now, defaultWeightUnit: .lb
        ))
        XCTAssertEqual(draft.exercises.count, 2)
        XCTAssertEqual(draft.totalSetCount, 4)
        XCTAssertEqual(draft.exercises.last?.sets.first?.distance, 50)
        let day = try XCTUnwrap(draft.performedAt)
        XCTAssertEqual(Self.stableCalendar.dateComponents([.year, .month, .day], from: day),
                       DateComponents(year: 2025, month: 1, day: 10))
    }

    func testRewriteDraftIgnoresADateTheSourceNeverStates() throws {
        let draft = try XCTUnwrap(Parser.rewriteDraft(
            fromModelText: "Date: 1/3/25\nBench Press 3x8 @ 185",
            source: "bench three sets of eight at 185",
            referenceDate: now, defaultWeightUnit: .lb
        ))
        XCTAssertNil(draft.performedAt)
    }

    func testRewriteDraftTakesUnitsFromTheSource() throws {
        let draft = try XCTUnwrap(Parser.rewriteDraft(
            fromModelText: "Squat 5x5 @ 100 lb",
            source: "squats five sets of five at 100 kg",
            referenceDate: now, defaultWeightUnit: .lb
        ))
        XCTAssertTrue(draft.exercises[0].sets.allSatisfy { $0.weightUnit == .kg })
    }

    func testRewriteDraftWithOnlyChatterIsNoCandidate() {
        XCTAssertNil(Parser.rewriteDraft(
            fromModelText: "Sure! Here is the workout:\n```\n```",
            source: "did some stuff", referenceDate: now, defaultWeightUnit: .lb
        ))
        XCTAssertNil(Parser.rewriteDraft(fromModelText: "", source: "x", referenceDate: now, defaultWeightUnit: .lb))
    }

    func testRewritePromptKeepsThePrewarmedPrefix() {
        XCTAssertTrue(Parser.rewriteInstructions.contains("Date: "))
        XCTAssertTrue(Parser.rewriteInstructions.contains("plain text"))
        XCTAssertTrue(Parser.pageImageNote(pageCount: 1).contains("text above is authoritative"))
        XCTAssertTrue(Parser.pageImageNote(pageCount: 2).contains("2 pages"))
    }

    // MARK: - Context budget

    func testByteBudgetDerivesFromTheContextWindow() {
        let base = Parser.inputByteBudget(contextSize: 4096)
        XCTAssertTrue((3_900...4_000).contains(base), "iOS 26 keeps roughly the old 4,000-byte cap, got \(base)")
        let advanced = Parser.inputByteBudget(contextSize: 8192)
        XCTAssertGreaterThan(advanced, base * 2, "An 8K model has more than twice the room once fixed costs are paid")
        XCTAssertEqual(Parser.inputByteBudget(contextSize: 1024), 0)
        XCTAssertEqual(Parser.inputByteBudget(contextSize: 0), 0)
        XCTAssertLessThanOrEqual(Parser.inputByteBudget(contextSize: 4095), base)
    }

    func testModelAttemptScalesWithTheContextWindow() {
        let medium = String(repeating: "Bench press 3x8 @ 185 rest 90s\n", count: 200)
        XCTAssertGreaterThan(medium.utf8.count, 4_000)
        XCTAssertFalse(Parser.canAttemptModel(for: medium))
        XCTAssertFalse(Parser.canAttemptModel(for: medium, contextSize: 4096))
        XCTAssertTrue(Parser.canAttemptModel(for: medium, contextSize: 8192))
        XCTAssertFalse(Parser.canAttemptModel(for: "  ", contextSize: 8192))
    }

    func testRewriteOverheadCoversItsInstructions() {
        // Plain prose runs ~4 characters per token; the constant must cover the
        // instructions or the pre-26.4 estimate would undercount.
        let estimate = Int((Double(Parser.rewriteInstructions.count) / 4.0).rounded(.up))
        XCTAssertGreaterThanOrEqual(Parser.rewriteOverheadTokens, estimate)
        XCTAssertLessThan(Parser.rewriteOverheadTokens, Parser.generateOverheadTokens,
                          "The plain-text rewrite has no schema overhead")
    }

    // MARK: - Model version

    func testModelVersionOnIOS26IsTheBaseModel() throws {
        if #available(iOS 27.0, *) {
            throw XCTSkip("Covers the iOS 26 runtime; iOS 27 reports its variant name.")
        }
        let version = OnDeviceModelVersion.current
        XCTAssertEqual(version.kind, .base26)
        XCTAssertEqual(version.displayName, "iOS 26 base model")
        XCTAssertEqual(version.contextSize, 4096)
        XCTAssertFalse(version.supportsVision)
        XCTAssertEqual(version.summary, "iOS 26 base model · 4096-token context")
    }

    func testLiveEvalThresholdsNeverDropBelowTheFloor() {
        XCTAssertEqual(FoundationModelsEvalThresholds.floor,
                       FoundationModelsEvalThresholds(corpus: 0.8, prose: 0.7, hard: 0.6))
        XCTAssertEqual(FoundationModelsEvalThresholds.forModel(.base26), .floor)
        for kind in OnDeviceModelVersion.Kind.allCases {
            XCTAssertTrue(FoundationModelsEvalThresholds.forModel(kind).isAtLeast(.floor), kind.rawValue)
        }
        XCTAssertTrue(FoundationModelsEvalThresholds.forModel(.coreAdvanced3)
            .isAtLeast(FoundationModelsEvalThresholds.forModel(.core3)))
    }

    // MARK: - Page images

    func testPageImagesScaleToTheModelBound() {
        XCTAssertTrue(WorkoutScanPageImage.scaledSize(width: 4032, height: 3024, maxDimension: 1024) == (1024, 768))
        XCTAssertTrue(WorkoutScanPageImage.scaledSize(width: 3024, height: 4032, maxDimension: 1024) == (768, 1024))
        XCTAssertTrue(WorkoutScanPageImage.scaledSize(width: 800, height: 600, maxDimension: 1024) == (800, 600))
        XCTAssertTrue(WorkoutScanPageImage.scaledSize(width: 0, height: 600, maxDimension: 1024) == (0, 0))
        XCTAssertTrue(WorkoutScanPageImage.scaledSize(width: 10_000, height: 1, maxDimension: 1024) == (1024, 1))
    }

    func testDownscaledPageKeepsOrientation() throws {
        let page = WorkoutScanPageImage(cgImage: try makeImage(width: 2048, height: 1024), orientation: .right)
        let scaled = try XCTUnwrap(page.downscaled())
        XCTAssertEqual(scaled.cgImage.width, 1024)
        XCTAssertEqual(scaled.cgImage.height, 512)
        XCTAssertEqual(scaled.orientation, .right)

        let small = WorkoutScanPageImage(cgImage: try makeImage(width: 300, height: 200))
        XCTAssertTrue(try XCTUnwrap(small.downscaled()).cgImage === small.cgImage, "Small pages are not redrawn")
    }

    func testTooManyPagesAreReadFromTextAlone() throws {
        let page = WorkoutScanPageImage(cgImage: try makeImage(width: 64, height: 64))
        XCTAssertEqual(WorkoutScanPageImage.modelReady([page, page]).count, 2)
        XCTAssertTrue(WorkoutScanPageImage.modelReady(Array(repeating: page, count: WorkoutScanPageImage.maximumModelPages + 1)).isEmpty)
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    // MARK: - Show sources

    func testSourceExcerptIsTheExercisesOwnLine() {
        let source = "Warmed up, then bench 3 sets of 8 at 185 lb. Finished with planks, 3 x 45 seconds"
        XCTAssertEqual(WorkoutDraftArbiter.sourceExcerpt(for: "Bench Press", in: source), "bench 3 sets of 8 at 185 lb")
        XCTAssertEqual(WorkoutDraftArbiter.sourceExcerpt(for: "Plank", in: source), "Finished with planks, 3 x 45 seconds")
        XCTAssertNil(WorkoutDraftArbiter.sourceExcerpt(for: "Deadlift", in: source))
    }

    func testSourceExcerptFlattensContinuationRowsAndTruncates() throws {
        let headed = "Squat\n5x5 @ 225\nrest 90s"
        XCTAssertEqual(WorkoutDraftArbiter.sourceExcerpt(for: "Squat", in: headed), "Squat / 5x5 @ 225 / rest 90s")

        let long = "Bench " + String(repeating: "heavy sets again ", count: 20)
        let excerpt = try XCTUnwrap(WorkoutDraftArbiter.sourceExcerpt(for: "Bench", in: long, limit: 40))
        XCTAssertEqual(excerpt.count, 40)
        XCTAssertTrue(excerpt.hasSuffix("…"))
    }

    func testOnlyModelReadingsCarrySourceExcerpts() {
        let source = "bench three sets of eight at 185"
        let exercises = [ParsedExerciseDraft(name: "Bench Press", sets: [ParsedSetDraft(weight: 185, reps: 8)])]
        let deterministic = ParsedWorkoutDraft(exercises: exercises)
        XCTAssertNil(WorkoutDraftArbiter.annotatingSourceExcerpts(deterministic, sourceText: source)
            .exercises[0].sourceExcerpt)

        let model = ParsedWorkoutDraft(exercises: exercises, interpretedByModel: true)
        XCTAssertEqual(WorkoutDraftArbiter.annotatingSourceExcerpts(model, sourceText: source)
            .exercises[0].sourceExcerpt, source)
    }

    func testDraftsSavedBeforeSourceExcerptsStillDecode() throws {
        var exercise = ParsedExerciseDraft(name: "Bench", sets: [ParsedSetDraft(reps: 5)])
        exercise.sourceExcerpt = "bench 5"
        let encoded = try JSONEncoder().encode(exercise)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["sourceExcerpt"] as? String, "bench 5")
        object.removeValue(forKey: "sourceExcerpt")
        let legacy = try JSONDecoder().decode(
            ParsedExerciseDraft.self, from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertNil(legacy.sourceExcerpt)
        XCTAssertEqual(legacy.name, "Bench")
    }

    // MARK: - Feedback

    private func ephemeralDefaults() -> UserDefaults {
        let name = "OnDeviceModelSupportTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testFeedbackStoreKeepsOnlyCounts() {
        let defaults = ephemeralDefaults()
        let store = ModelReadFeedbackStore(defaults: defaults)
        store.record(.correct)
        store.record(.correct)
        store.record(.incorrect)
        XCTAssertEqual(store.count(.correct), 2)
        XCTAssertEqual(store.count(.incorrect), 1)
        XCTAssertEqual(Set(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("modelReadFeedback") }),
                       [ModelReadFeedbackStore.correctCountKey, ModelReadFeedbackStore.incorrectCountKey])
    }

    func testShareTextPairsTheSourceWithMarblesReading() {
        let draft = ParsedWorkoutDraft(exercises: [
            ParsedExerciseDraft(name: "Bench Press", sets: Array(repeating: ParsedSetDraft(weight: 185, reps: 8), count: 3)),
            ParsedExerciseDraft(name: "Bounds", sets: [ParsedSetDraft(), ParsedSetDraft()]),
            ParsedExerciseDraft(name: "Sprint", sets: [ParsedSetDraft(distance: 50, distanceUnit: .meters)]),
            ParsedExerciseDraft(name: "Ramp", sets: [
                ParsedSetDraft(weight: 135, weightUnit: .kg, reps: 5),
                ParsedSetDraft(weight: 152.5, weightUnit: .kg, reps: 3),
            ]),
        ], interpretedByModel: true)
        let text = ModelReadExample.shareText(source: "  bench 3x8 at 185 ...  ", draft: draft, modelName: "iOS 26 base model")
        XCTAssertEqual(text, """
            Marble misread this workout (on-device Apple Intelligence, iOS 26 base model).

            What I wrote:
            bench 3x8 at 185 ...

            What Marble read:
            - Bench Press: 3 sets of 8 reps @ 185 lb
            - Bounds: 2 sets
            - Sprint: 1 set of 50 m
            - Ramp: 5 reps @ 135 kg; 3 reps @ 152.5 kg
            """)
    }

    private struct ModelDraftParser: WorkoutScanParsing {
        func parse(ocrText: String, referenceDate: Date) async -> ParsedWorkoutDraft {
            ParsedWorkoutDraft(exercises: [
                ParsedExerciseDraft(name: "Bench Press", sets: [ParsedSetDraft(weight: 185, reps: 8)])
            ], interpretedByModel: true)
        }

        func parse(
            ocrText: String,
            referenceDate: Date,
            pageImages: [WorkoutScanPageImage],
            onStage: WorkoutParseStageHandler
        ) async -> ParsedWorkoutDraft {
            await onStage(.interpreting(pass: 1, of: 2))
            await onStage(.partialNotation(lines: ["Bench Press 1x8 @ 185"]))
            await onStage(.finalizing)
            return await parse(ocrText: ocrText, referenceDate: referenceDate)
        }
    }

    func testTextEntryRecordsOneVerdictPerModelReview() async {
        let defaults = ephemeralDefaults()
        let store = ModelReadFeedbackStore(defaults: defaults)
        let viewModel = WorkoutTextEntryViewModel(parser: ModelDraftParser(), feedbackStore: store)
        viewModel.text = "Hit chest hard this morning, felt great"

        await viewModel.preview(in: makeInMemoryContext())

        XCTAssertEqual(viewModel.phase, .review)
        XCTAssertEqual(viewModel.streamedNotationLines, ["Bench Press 1x8 @ 185"],
                       "Streamed lines reach the processing UI through the staged requirement")
        XCTAssertNil(viewModel.modelReadVerdict)
        viewModel.recordModelReadFeedback(.incorrect)
        viewModel.recordModelReadFeedback(.correct)
        XCTAssertEqual(viewModel.modelReadVerdict, .incorrect)
        XCTAssertEqual(store.count(.incorrect), 1)
        XCTAssertEqual(store.count(.correct), 0)
        XCTAssertTrue(viewModel.modelReadShareText.contains("Hit chest hard this morning, felt great"))
        XCTAssertTrue(viewModel.modelReadShareText.contains("- Bench Press: 1 set of 8 reps @ 185 lb"))

        await viewModel.preview(in: makeInMemoryContext())
        XCTAssertNil(viewModel.modelReadVerdict, "A new reading asks again")
    }

    func testDeterministicReviewsDoNotAskForFeedback() async {
        let store = ModelReadFeedbackStore(defaults: ephemeralDefaults())
        let viewModel = WorkoutTextEntryViewModel(parser: HeuristicWorkoutScanParser(), feedbackStore: store)
        viewModel.text = "Bench 3x8 @ 185"
        await viewModel.preview(in: makeInMemoryContext())
        viewModel.recordModelReadFeedback(.correct)
        XCTAssertNil(viewModel.modelReadVerdict)
        XCTAssertEqual(store.count(.correct), 0)
    }

    // MARK: - Scan threading

    private final class ImageSpyParser: WorkoutScanParsing, @unchecked Sendable {
        var receivedImages: [WorkoutScanPageImage] = []
        func parse(ocrText: String, referenceDate: Date) async -> ParsedWorkoutDraft {
            ParsedWorkoutDraft(exercises: [
                ParsedExerciseDraft(name: "Squat", sets: [ParsedSetDraft(weight: 100, reps: 5)])
            ], interpretedByModel: true)
        }

        func parse(
            ocrText: String,
            referenceDate: Date,
            pageImages: [WorkoutScanPageImage],
            onStage: WorkoutParseStageHandler
        ) async -> ParsedWorkoutDraft {
            receivedImages = pageImages
            await onStage(.partialNotation(lines: ["Squat 1x5 @ 100"]))
            return await parse(ocrText: ocrText, referenceDate: referenceDate)
        }
    }

    private struct StubRecognizer: WorkoutTextRecognizing {
        let text: String
        func recognizeText(in image: CGImage) async throws -> String { text }
    }

    func testScanHandsPageImagesToTheParserWithOCR() async throws {
        let spy = ImageSpyParser()
        let store = ModelReadFeedbackStore(defaults: ephemeralDefaults())
        let viewModel = WorkoutScanViewModel(
            recognizer: StubRecognizer(text: "Legs today, went heavy and felt strong"), parser: spy,
            defaultWeightUnit: .kg, feedbackStore: store
        )
        let first = try makeImage(width: 40, height: 30)
        let second = try makeImage(width: 30, height: 40)
        await viewModel.process(
            pages: [(first, Data("a".utf8)), (second, Data("b".utf8))],
            orientations: [.right],
            in: makeInMemoryContext()
        )

        XCTAssertEqual(viewModel.phase, .review)
        XCTAssertEqual(spy.receivedImages.count, 2)
        guard spy.receivedImages.count == 2 else { return }
        XCTAssertTrue(spy.receivedImages[0].cgImage === first)
        XCTAssertEqual(spy.receivedImages[0].orientation, .right)
        XCTAssertEqual(spy.receivedImages[1].orientation, .up, "Missing orientations default to up")
        XCTAssertEqual(viewModel.streamedNotationLines, ["Squat 1x5 @ 100"])
        XCTAssertEqual(viewModel.sourceText, WorkoutScanViewModel.joinOCR(Array(repeating: "Legs today, went heavy and felt strong", count: 2)),
                       "Both pages' OCR, joined")

        viewModel.recordModelReadFeedback(.correct)
        XCTAssertEqual(viewModel.modelReadVerdict, .correct)
        XCTAssertEqual(store.count(.correct), 1)
        XCTAssertTrue(viewModel.modelReadShareText.contains("Legs today, went heavy and felt strong"))

        viewModel.reset()
        XCTAssertNil(viewModel.modelReadVerdict)
        XCTAssertTrue(viewModel.streamedNotationLines.isEmpty)
        XCTAssertEqual(viewModel.sourceText, "")
    }

    /// Before the staged parse was a protocol requirement, a call through
    /// `any WorkoutScanParsing` hit the extension default and the on-device
    /// parser's stages never reached the UI.
    func testStagesReachTheUIThroughTheExistential() async {
        let parser: any WorkoutScanParsing = FoundationModelsWorkoutScanParser()
        let recorder = StageLog()
        _ = await parser.parse(
            ocrText: "1/10/25\nBounds (2 sets)\nSprints 2 sets, 50m each",
            referenceDate: now
        ) { stage in await recorder.append(stage) }
        let stages = await recorder.stages
        XCTAssertEqual(stages, [.readingNotation, .finalizing])
    }

    private actor StageLog {
        var stages: [WorkoutParseStage] = []
        func append(_ stage: WorkoutParseStage) { stages.append(stage) }
    }

    func testUIImageOrientationMapsToImageIO() {
        XCTAssertEqual(WorkoutScanViewModel.propertyOrientation(.up), .up)
        XCTAssertEqual(WorkoutScanViewModel.propertyOrientation(.right), .right)
        XCTAssertEqual(WorkoutScanViewModel.propertyOrientation(.leftMirrored), .leftMirrored)
    }

    // MARK: - Availability copy

    private let statuses: [ModelAvailabilityStatus] = [
        .available, .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady, .unknown,
    ]

    func testCaptionsNameTheActualReason() {
        XCTAssertEqual(ModelAvailabilityStatus.available.privacyCaption(),
                       "Read on your device with Apple Intelligence — nothing is uploaded.")
        let ineligible = ModelAvailabilityStatus.deviceNotEligible.privacyCaption()
        XCTAssertTrue(ineligible.contains("doesn't support Apple Intelligence"))
        XCTAssertTrue(ineligible.contains("Gym notation still works on device"))
        XCTAssertTrue(ModelAvailabilityStatus.modelNotReady.privacyCaption().contains("still downloading"))
        XCTAssertTrue(ModelAvailabilityStatus.appleIntelligenceNotEnabled
            .privacyCaption(canTurnOnAppleIntelligence: true).contains("Turn on Apple Intelligence"))
        for status in statuses {
            XCTAssertTrue(status.privacyCaption().contains("nothing is uploaded"), "\(status)")
        }
    }

    func testIOS27CopyNeverAsksToTurnOnAppleIntelligence() {
        for status in statuses {
            let caption = status.privacyCaption(canTurnOnAppleIntelligence: false)
            XCTAssertFalse(caption.localizedCaseInsensitiveContains("turn on"), caption)
            let note = status.unavailableNote(canTurnOnAppleIntelligence: false) ?? ""
            XCTAssertFalse(note.localizedCaseInsensitiveContains("turn it on"), note)
            XCTAssertFalse(note.localizedCaseInsensitiveContains("turned off"), note)
        }
    }

    func testCurrentRuntimeDecidesWhetherAppleIntelligenceCanBeOff() {
        if #available(iOS 27.0, *) {
            XCTAssertFalse(ModelAvailabilityStatus.canTurnOnAppleIntelligence)
        } else {
            XCTAssertTrue(ModelAvailabilityStatus.canTurnOnAppleIntelligence)
        }
    }

    func testUnavailableIssueNotesUseTheReason() {
        typealias VM = WorkoutTextEntryViewModel
        XCTAssertEqual(VM.modelIssueNote(for: .unavailable, availability: .deviceNotEligible),
                       "This iPhone doesn't support Apple Intelligence, so only gym notation was read.")
        XCTAssertTrue(VM.modelIssueNote(for: .unavailable, availability: .modelNotReady).contains("still downloading"))
        XCTAssertEqual(VM.modelIssueNote(for: .unavailable, availability: .available),
                       "Apple Intelligence couldn't read this right now, so only gym notation was read.",
                       "A cool-down after a failure keeps the generic copy")
        XCTAssertTrue(VM.modelIssueNote(for: .unavailable, availability: .appleIntelligenceNotEnabled,
                                        canTurnOnAppleIntelligence: true).contains("Turn it on in Settings"))
        XCTAssertFalse(VM.modelIssueNote(for: .unavailable, availability: .appleIntelligenceNotEnabled,
                                         canTurnOnAppleIntelligence: false).contains("Settings"))
        XCTAssertTrue(VM.modelIssueNote(for: .inputTooLong, availability: .available).contains("blank line"))
    }
}
