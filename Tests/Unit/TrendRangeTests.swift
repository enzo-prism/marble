import XCTest
@testable import marble

@MainActor
final class TrendRangeTests: MarbleTestCase {
    func testLabels() {
        let expected: [TrendRange: String] = [
            .sevenDays: "7D",
            .thirtyDays: "30D",
            .ninetyDays: "90D",
            .oneYear: "1Y",
            .all: "All"
        ]

        for range in TrendRange.allCases {
            XCTAssertEqual(range.label, expected[range])
        }
    }

    func testStartDatesUseFixedNow() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)

        let expectedSeven = calendar.date(byAdding: .day, value: -6, to: startOfDay)
        let expectedThirty = calendar.date(byAdding: .day, value: -29, to: startOfDay)
        let expectedNinety = calendar.date(byAdding: .day, value: -89, to: startOfDay)
        let expectedYear = calendar.date(byAdding: .year, value: -1, to: startOfDay)
            .flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }

        XCTAssertEqual(TrendRange.sevenDays.startDate, expectedSeven)
        XCTAssertEqual(TrendRange.thirtyDays.startDate, expectedThirty)
        XCTAssertEqual(TrendRange.ninetyDays.startDate, expectedNinety)
        XCTAssertEqual(TrendRange.oneYear.startDate, expectedYear)
        XCTAssertNil(TrendRange.all.startDate)
    }

    func testOneYearWindowHoldsOneYearOfDays() throws {
        let calendar = Calendar.current
        let start = try XCTUnwrap(TrendRange.oneYear.startDate)
        let today = calendar.startOfDay(for: now)
        let days = try XCTUnwrap(calendar.dateComponents([.day], from: start, to: today).day) + 1
        XCTAssertTrue((365...366).contains(days), "1Y spans \(days) days")
    }
}
