import XCTest
@testable import marble

@MainActor
final class WorkoutSessionSegmenterTests: MarbleTestCase {
    func testSingleWorkoutStaysOneSegment() {
        let text = """
        Push day
        Bench 3x8 @ 185
        Squat 5x5 @ 225
        """
        XCTAssertEqual(WorkoutSessionSegmenter.segments(from: text, referenceDate: now).count, 1)
    }

    func testDateHeadersSplitSessions() {
        let text = """
        3/5
        Bench 3x8 @ 185

        3/6
        Squat 5x5 @ 225
        """
        let segments = WorkoutSessionSegmenter.segments(from: text, referenceDate: now)
        XCTAssertEqual(segments.count, 2)
        XCTAssertTrue(segments[0].contains("Bench"))
        XCTAssertTrue(segments[1].contains("Squat"))
        XCTAssertFalse(segments[0].contains("Squat"))
    }

    func testRelativeDateHeadersSplitSessions() {
        let text = """
        Yesterday
        Bench 3x8 @ 185

        Today
        Squat 5x5
        """
        XCTAssertEqual(WorkoutSessionSegmenter.segments(from: text, referenceDate: now).count, 2)
    }

    func testDateOnSetLineDoesNotSplit() {
        let text = """
        3/5 Bench 3x8 @ 185
        Squat 5x5 @ 225
        """
        XCTAssertEqual(WorkoutSessionSegmenter.segments(from: text, referenceDate: now).count, 1)
    }

    func testWeekdayHeadersSplitSessions() {
        let text = """
        Monday
        Bench 3x8 @ 185

        Tuesday
        Squat 5x5 @ 225
        """
        let segments = WorkoutSessionSegmenter.segments(from: text, referenceDate: now)
        XCTAssertEqual(segments.count, 2)
        XCTAssertTrue(segments[0].contains("Bench"))
        XCTAssertTrue(segments[1].contains("Squat"))
    }

    func testMonthNameHeadersSplitSessions() {
        let text = """
        March 5
        Bench 3x8 @ 185

        6 March
        Squat 5x5
        """
        XCTAssertEqual(WorkoutSessionSegmenter.segments(from: text, referenceDate: now).count, 2)
    }

    func testTitledDateLineSplitsAfterContent() {
        let text = """
        Push day 3/5
        Bench 3x8 @ 185

        Pull day 3/6
        Row 3x10
        """
        XCTAssertEqual(WorkoutSessionSegmenter.segments(from: text, referenceDate: now).count, 2)
    }

    func testEmptyTextReturnsNoSegments() {
        XCTAssertTrue(WorkoutSessionSegmenter.segments(from: "  \n ", referenceDate: now).isEmpty)
    }

    func testNumberedDayHeadersSplitSessions() {
        let text = """
        Day 1
        Bench 3x8 @ 185

        Day 2: Legs
        Squat 5x5
        """
        let segments = WorkoutSessionSegmenter.segments(from: text, referenceDate: now)
        XCTAssertEqual(segments.count, 2)
        XCTAssertTrue(segments[0].contains("Bench"))
        XCTAssertTrue(segments[1].contains("Squat"))
    }

    func testNumberedSessionHeaderWithSetSpecDoesNotSplit() {
        let text = """
        Push day
        Day 1 Bench 3x8 @ 185
        Squat 5x5
        """
        XCTAssertEqual(WorkoutSessionSegmenter.segments(from: text, referenceDate: now).count, 1)
        XCTAssertFalse(HandwrittenWorkoutParser.isNumberedSessionHeader("Day 1 Bench 3x8 @ 185"))
    }
}

@MainActor
final class HandwrittenWorkoutParserSessionHeaderTests: MarbleTestCase {
    func testBareDateIsHeader() {
        XCTAssertTrue(HandwrittenWorkoutParser.isSessionDateHeader("3/5", referenceDate: now))
        XCTAssertTrue(HandwrittenWorkoutParser.isSessionDateHeader("2025-03-05", referenceDate: now))
        XCTAssertTrue(HandwrittenWorkoutParser.isSessionDateHeader("yesterday", referenceDate: now))
    }

    func testDateWithExerciseIsNotHeader() {
        XCTAssertFalse(HandwrittenWorkoutParser.isSessionDateHeader("3/5 Bench 3x8 @ 185", referenceDate: now))
        XCTAssertFalse(HandwrittenWorkoutParser.isSessionDateHeader("yesterday bench 3x8", referenceDate: now))
    }

    func testTitleWithDateIsHeader() {
        XCTAssertTrue(HandwrittenWorkoutParser.isSessionDateHeader("Push day 3/5", referenceDate: now))
        XCTAssertTrue(HandwrittenWorkoutParser.isSessionDateHeader("Monday 3/5", referenceDate: now))
    }

    func testBareWeekdayIsHeader() {
        XCTAssertTrue(HandwrittenWorkoutParser.isSessionDateHeader("Monday", referenceDate: now))
        XCTAssertTrue(HandwrittenWorkoutParser.isSessionDateHeader("Tue", referenceDate: now))
        XCTAssertFalse(HandwrittenWorkoutParser.isSessionDateHeader("Monday Bench 3x8", referenceDate: now))
    }

    func testMonthNameIsHeader() {
        XCTAssertTrue(HandwrittenWorkoutParser.isSessionDateHeader("March 5", referenceDate: now))
        XCTAssertTrue(HandwrittenWorkoutParser.isSessionDateHeader("5 March 2025", referenceDate: now))
        XCTAssertFalse(HandwrittenWorkoutParser.isSessionDateHeader("March 5x5 @ 185", referenceDate: now))
    }

    func testOCRPunctuationOnWeekdayIsStillAHeader() {
        XCTAssertTrue(HandwrittenWorkoutParser.isSessionDateHeader("Monday.", referenceDate: now))
        XCTAssertTrue(HandwrittenWorkoutParser.isSessionDateHeader("Tuesday:", referenceDate: now))
        XCTAssertTrue(HandwrittenWorkoutParser.isSessionDateHeader("- Monday -", referenceDate: now))
    }

    func testNumberedDayAndSessionHeaders() {
        XCTAssertTrue(HandwrittenWorkoutParser.isNumberedSessionHeader("Day 1"))
        XCTAssertTrue(HandwrittenWorkoutParser.isNumberedSessionHeader("Day 2: Legs"))
        XCTAssertTrue(HandwrittenWorkoutParser.isNumberedSessionHeader("Session 3"))
        XCTAssertTrue(HandwrittenWorkoutParser.isSessionSplitHeader("Workout 2", referenceDate: now))
        XCTAssertFalse(HandwrittenWorkoutParser.isNumberedSessionHeader("Day 1 Bench 3x8 @ 185"))
        XCTAssertFalse(HandwrittenWorkoutParser.isSessionDateHeader("Day 1", referenceDate: now))
        XCTAssertEqual(HandwrittenWorkoutParser.numberedSessionHeaderRemainder("Day 2: Legs"), "Legs")
        XCTAssertEqual(HandwrittenWorkoutParser.numberedSessionHeaderRemainder("Day 1"), "")
        XCTAssertNil(HandwrittenWorkoutParser.numberedSessionHeaderRemainder("Day 1 Bench 3x8 @ 185"))
    }

    func testFalseMondayOnASetLineDoesNotSplit() {
        let text = """
        Push day
        Bench 3x8 Monday
        Squat 5x5
        """
        XCTAssertEqual(WorkoutSessionSegmenter.segments(from: text, referenceDate: now).count, 1)
        XCTAssertFalse(HandwrittenWorkoutParser.isSessionDateHeader("Bench 3x8 Monday", referenceDate: now))
    }

    func testOCRJoinedWeekdayPagesSplit() {
        let text = WorkoutScanViewModel.joinOCR([
            "Monday\nBench 3x8 @ 185",
            "Tuesday.\nSquat 5x5"
        ])
        let segments = WorkoutSessionSegmenter.segments(from: text, referenceDate: now)
        XCTAssertEqual(segments.count, 2)
        XCTAssertTrue(segments[0].contains("Bench"))
        XCTAssertTrue(segments[1].contains("Squat"))
    }
}
