import XCTest
@testable import marble

final class SprintTimingTests: XCTestCase {
    func testTenthsFromSecondsRoundsToNearest() {
        XCTAssertEqual(SprintTiming.tenths(fromSeconds: 14.8), 148)
        XCTAssertEqual(SprintTiming.tenths(fromSeconds: 14.84), 148)
        XCTAssertEqual(SprintTiming.tenths(fromSeconds: 14.85), 149)
        XCTAssertEqual(SprintTiming.tenths(fromSeconds: 15.0), 150)
    }

    func testWholeSecondsRoundTrip() {
        XCTAssertEqual(SprintTiming.tenths(fromWholeSeconds: 19), 190)
        XCTAssertEqual(SprintTiming.wholeSeconds(fromTenths: 148), 15)
        XCTAssertEqual(SprintTiming.wholeSeconds(fromTenths: 144), 14)
        XCTAssertEqual(SprintTiming.wholeSeconds(fromTenths: 145), 15)
        XCTAssertEqual(SprintTiming.seconds(fromTenths: 148), 14.8, accuracy: 0.0001)
    }

    func testTextFormatting() {
        XCTAssertEqual(SprintTiming.text(tenths: 148), "14.8s")
        XCTAssertEqual(SprintTiming.text(tenths: 150), "15.0s")
        XCTAssertEqual(SprintTiming.text(tenths: 90), "9.0s")
        XCTAssertEqual(SprintTiming.text(tenths: 624), "1:02.4")
        XCTAssertEqual(SprintTiming.text(tenths: 600), "1:00.0")
    }

    func testDeltaText() {
        XCTAssertEqual(SprintTiming.deltaText(tenths: 4), "0.4 seconds")
        XCTAssertEqual(SprintTiming.deltaText(tenths: 10), "1 second")
        XCTAssertEqual(SprintTiming.deltaText(tenths: 20), "2 seconds")
        XCTAssertEqual(SprintTiming.deltaText(tenths: 25), "2.5 seconds")
        XCTAssertEqual(SprintTiming.deltaText(tenths: -4), "0.4 seconds")
    }

    func testInputParsing() {
        XCTAssertEqual(SprintTiming.tenths(fromInput: "14.8"), 148)
        XCTAssertEqual(SprintTiming.tenths(fromInput: "14,8"), 148)
        XCTAssertEqual(SprintTiming.tenths(fromInput: "15"), 150)
        XCTAssertEqual(SprintTiming.tenths(fromInput: " 9.5 "), 95)
        XCTAssertNil(SprintTiming.tenths(fromInput: ""))
        XCTAssertNil(SprintTiming.tenths(fromInput: "abc"))
        XCTAssertNil(SprintTiming.tenths(fromInput: "0"))
        XCTAssertNil(SprintTiming.tenths(fromInput: "-3"))
        // Beyond the 30-minute plausibility ceiling.
        XCTAssertNil(SprintTiming.tenths(fromInput: "1801"))
    }

    func testInputTextDropsTrailingZero() {
        XCTAssertEqual(SprintTiming.inputText(fromTenths: 148), "14.8")
        XCTAssertEqual(SprintTiming.inputText(fromTenths: 150), "15")
        XCTAssertEqual(SprintTiming.inputText(fromTenths: 95), "9.5")
    }

    func testPlausibility() {
        XCTAssertFalse(SprintTiming.isPlausible(tenths: 0))
        XCTAssertTrue(SprintTiming.isPlausible(tenths: 1))
        XCTAssertTrue(SprintTiming.isPlausible(tenths: SprintTiming.maxTenths))
        XCTAssertFalse(SprintTiming.isPlausible(tenths: SprintTiming.maxTenths + 1))
    }
}
