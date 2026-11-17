import SwiftData
import XCTest
@testable import marble

/// Visual Intelligence must answer fast and stay silent unless what it read is a
/// workout. The decision is the deterministic parser's, tested here on the kinds of
/// text the camera and screenshots produce.
@MainActor
final class WorkoutVisualSearchTests: MarbleTestCase {
    // MARK: - Relevance

    func testWhiteboardWODIsAWorkout() {
        let text = """
        WOD
        5 rounds for time
        10 thrusters 95 lb
        15 pull-ups
        200m run
        """
        XCTAssertTrue(WorkoutVisualSearch.isPlausibleWorkout(text, referenceDate: now))
        XCTAssertNotNil(WorkoutVisualSearch.result(forRecognizedText: text, referenceDate: now))
    }

    func testProgramScreenshotTableRowsAreAWorkout() {
        // One line per table row, as the structured document recognizer emits them.
        let text = """
        Week 3 Day 1
        Back Squat 5x5 225
        Bench Press 3x8 @ 155 lb
        Romanian Deadlift 3x10 135
        """
        XCTAssertTrue(WorkoutVisualSearch.isPlausibleWorkout(text, referenceDate: now))
    }

    func testCoachMessageWithoutNotationKeywordsIsAWorkout() {
        let text = """
        Deadlift 315x5
        Bench 225x3
        """
        XCTAssertTrue(WorkoutVisualSearch.isPlausibleWorkout(text, referenceDate: now))
    }

    func testEmptyAndShortTextIsNotAWorkout() {
        XCTAssertFalse(WorkoutVisualSearch.isPlausibleWorkout("", referenceDate: now))
        XCTAssertFalse(WorkoutVisualSearch.isPlausibleWorkout("  \n ", referenceDate: now))
        XCTAssertFalse(WorkoutVisualSearch.isPlausibleWorkout("9:41", referenceDate: now))
        XCTAssertNil(WorkoutVisualSearch.result(forRecognizedText: "", referenceDate: now))
    }

    func testProseWithoutWorkoutNotationIsNotAWorkout() {
        let article = """
        The city council met on Tuesday to discuss the new budget.
        Officials said the plan would take effect next spring.
        Residents can comment online until the end of the month.
        """
        XCTAssertFalse(WorkoutVisualSearch.isPlausibleWorkout(article, referenceDate: now))
    }

    func testReceiptIsNotAWorkout() {
        let receipt = """
        FRESH MARKET
        Store 0412  Register 3
        Thank you for shopping with us
        Visit us online for weekly deals
        Questions? Call our help line
        SUBTOTAL 18.47
        """
        XCTAssertFalse(WorkoutVisualSearch.isPlausibleWorkout(receipt, referenceDate: now))
    }

    func testPriceListIsNotAWorkout() {
        let receipt = """
        Milk 3.99
        Bread 2.49
        Eggs 4.29
        Coffee 11.50
        """
        XCTAssertFalse(WorkoutVisualSearch.isPlausibleWorkout(receipt, referenceDate: now))
    }

    func testLoadsWithoutSetNotationAreAWorkout() {
        let text = """
        Bench 225
        Squat 315
        Deadlift 405
        """
        XCTAssertTrue(WorkoutVisualSearch.isPlausibleWorkout(text, referenceDate: now))
    }

    func testTrainingNotationMarkers() {
        XCTAssertTrue(WorkoutVisualSearch.containsTrainingNotation("Squat 5 x 5"))
        XCTAssertTrue(WorkoutVisualSearch.containsTrainingNotation("pushups 3×AMRAP"))
        XCTAssertTrue(WorkoutVisualSearch.containsTrainingNotation("EMOM 10 min"))
        XCTAssertTrue(WorkoutVisualSearch.containsTrainingNotation("bench 8 reps"))
        XCTAssertFalse(WorkoutVisualSearch.containsTrainingNotation("Prepared 4 servings"))
    }

    // MARK: - Entity

    override func tearDown() {
        WorkoutCaptureCache.removeAll()
        super.tearDown()
    }

    func testEntityIdentifierIsOpaqueAndResolvesFromTheCache() throws {
        let text = "Bench 3x8 @ 185\nSquat 5x5 225"
        let entity = WorkoutCaptureEntity(text: text)
        XCTAssertNotNil(UUID(uuidString: entity.id), "The identifier is a random token.")
        XCTAssertFalse(entity.id.contains("Bench"), "Recognized text never appears in the identifier.")
        XCTAssertNotEqual(WorkoutCaptureEntity(text: text).id, entity.id)
        XCTAssertEqual(try XCTUnwrap(WorkoutCaptureEntity(id: entity.id)).text, text)
        XCTAssertNil(WorkoutCaptureEntity(id: "something-else"))
        XCTAssertNil(WorkoutCaptureEntity(id: UUID().uuidString), "An unknown token (e.g. after relaunch) resolves to nothing.")
    }

    func testCapturesExpireAfterTenMinutes() {
        let entity = WorkoutCaptureEntity(text: "Deadlift 315x5", now: now)
        XCTAssertNotNil(WorkoutCaptureEntity(id: entity.id, now: now.addingTimeInterval(9 * 60)))
        XCTAssertNil(WorkoutCaptureEntity(id: entity.id, now: now.addingTimeInterval(10 * 60)))
    }

    func testCacheIsBounded() {
        let first = WorkoutCaptureEntity(text: "Squat 5x5", now: now)
        let rest = (0..<WorkoutCaptureCache.capacity).map { WorkoutCaptureEntity(text: "Row \($0)x10", now: now) }
        XCTAssertNil(WorkoutCaptureEntity(id: first.id, now: now), "The oldest capture is evicted.")
        XCTAssertNotNil(WorkoutCaptureEntity(id: rest[0].id, now: now))
    }

    func testOpenIntentIsNotAShortcutsAction() {
        XCTAssertFalse(OpenWorkoutCaptureIntent.isDiscoverable)
    }

    func testQueryResolvesOnlyLiveTokens() async throws {
        let entity = WorkoutCaptureEntity(text: "Deadlift 315x5")
        let resolved = try await WorkoutCaptureQuery().entities(for: [entity.id, "unknown", UUID().uuidString])
        XCTAssertEqual(resolved.map(\.text), ["Deadlift 315x5"])
    }

    func testLongCapturesAreTrimmedAtALineBoundary() {
        let line = String(repeating: "a", count: 99)
        let text = Array(repeating: line, count: 60).joined(separator: "\n")
        let bounded = WorkoutCaptureEntity.bounded(text)
        XCTAssertLessThanOrEqual(bounded.count, WorkoutCaptureEntity.maximumTextLength)
        XCTAssertTrue(bounded.split(separator: "\n").allSatisfy { $0.count == 99 }, "No line is cut mid-way.")
    }

    func testPreviewShowsTheFirstRecognizedLines() {
        let preview = WorkoutCaptureEntity.preview(of: "\nBack Squat 5x5\n\nBench 3x8\nRows 3x10\nCurls 3x12")
        XCTAssertEqual(preview, "Back Squat 5x5 · Bench 3x8 · Rows 3x10 …")
        XCTAssertLessThanOrEqual(WorkoutCaptureEntity.preview(of: String(repeating: "Squat 5x5 ", count: 40)).count, 90)
    }

    func testOpeningAResultStagesEditableReviewWithoutSaving() async throws {
        let container = makeInMemoryContainer()
        AppIntentsSupport.register(container: container)
        defer { AppIntentsSupport.container = nil; _ = PendingTextImport.consume() }
        let text = "Bench 3x8 @ 185"

        OpenWorkoutCaptureIntent.stageForReview(text, notify: false)
        XCTAssertEqual(PendingTextImport.consume(), text)

        // The intent itself stages the same text and asks the Add composer to open it.
        let opened = expectation(forNotification: .marbleOpenTextImport, object: nil)
        _ = try await OpenWorkoutCaptureIntent(target: WorkoutCaptureEntity(text: text)).perform()
        await fulfillment(of: [opened], timeout: 2)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<SetEntry>()), 0, "Nothing is saved before review.")
    }
}
