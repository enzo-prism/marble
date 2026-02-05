import XCTest
@testable import marble

final class DateHelperFormattingTests: MarbleTestCase {
    private let calendar = MarbleTestCase.stableCalendar

    func testFormattedDurationSecondsOnly() {
        XCTAssertEqual(DateHelper.formattedDuration(seconds: 45), "45s")
    }

    func testFormattedDurationMinutesOnly() {
        XCTAssertEqual(DateHelper.formattedDuration(seconds: 120), "2m")
    }

    func testFormattedDurationMinutesAndSeconds() {
        XCTAssertEqual(DateHelper.formattedDuration(seconds: 125), "2m 5s")
    }

    func testFormattedClockDuration() {
        XCTAssertEqual(DateHelper.formattedClockDuration(seconds: 90), "1:30")
    }

    func testMergeDayAndTime() {
        let day = makeDate(year: 2025, month: 1, day: 15, hour: 0, minute: 0)
        let time = makeDate(year: 2025, month: 1, day: 20, hour: 14, minute: 30)
        let merged = DateHelper.merge(day: day, time: time, calendar: calendar)
        let expected = makeDate(year: 2025, month: 1, day: 15, hour: 14, minute: 30)
        XCTAssertEqual(merged, expected)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}
