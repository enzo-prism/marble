import XCTest
@testable import marble

final class WorkoutNotationDurationTests: XCTestCase {
    func testExistingDurationForms() {
        for (token, expected) in [("24:30", 1470), ("1:02:03", 3723), ("1.5min", 90),
                                  ("45s", 45), ("2hours", 7200), ("0s", 0), ("0:90", 90)] {
            XCTAssertEqual(WorkoutNotationDuration.seconds(token), expected, token)
        }
    }

    func testOverflowAndNonfiniteInputIsRejected() {
        for token in ["1e100s", "infs", "nans", "9223372036854775807:00",
                      "0:9223372036854775807:59", "-1:30", "1:-30", "-1s", "1::30"] {
            XCTAssertNil(WorkoutNotationDuration.seconds(token), token)
        }
        XCTAssertNil(WorkoutNotationDuration.wholeSeconds(Double(Int.max)))
        XCTAssertNil(WorkoutNotationDuration.wholeSeconds(.infinity))
        XCTAssertNil(WorkoutNotationDuration.wholeSeconds(.nan))
    }

    func testMinuteAbbreviationIsNotAGeneralDuration() {
        XCTAssertNil(WorkoutNotationDuration.seconds("400m"))
    }
    func testCSVNumericOverflowIsRejected() {
        for input in ["inf", "nan", "1e100", "9223372036854775808"] {
            XCTAssertNil(CSVNumber.positiveInt(input), input)
            XCTAssertNil(CSVNumber.nonNegativeInt(input), input)
        }
        XCTAssertNil(CSVNumber.positiveDouble("inf"))
        XCTAssertNil(CSVNumber.rpe("inf"))
        XCTAssertEqual(CSVNumber.rpe("1e100"), 10)
        XCTAssertEqual(CSVNumber.nonNegativeInt("0"), 0)
        XCTAssertEqual(CSVNumber.positiveDouble("1.000,5", decimalComma: true), 1000.5)
        XCTAssertEqual(CSVNumber.display(1e100), String(1e100))
        XCTAssertEqual(CSVNumber.display(-12), "-12")
    }

    func testCSVWorkoutDurationOverflowIsRejected() {
        for input in ["9223372036854775807", "9223372036854775807:00",
                      "999999999999999999999999999999h", "9000000000000000000s 9000000000000000000s"] {
            XCTAssertNil(CSVNumber.workoutDurationToken(input), input)
        }
        XCTAssertEqual(CSVNumber.workoutDurationToken("1h 5m"), 3900)
        XCTAssertEqual(CSVNumber.workoutDurationToken("1:16:00"), 4560)
    }

}
