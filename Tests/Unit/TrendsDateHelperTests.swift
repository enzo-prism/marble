import XCTest
@testable import marble

final class TrendsDateHelperTests: MarbleTestCase {
    private let calendar = MarbleTestCase.stableCalendar

    func testStartAndEndOfWeek() {
        let date = makeDate(year: 2025, month: 1, day: 15, hour: 12)
        let expectedStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start
        XCTAssertEqual(TrendsDateHelper.startOfWeek(for: date, calendar: calendar), expectedStart)

        let expectedEnd = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 6, to: expectedStart ?? date) ?? date)
        XCTAssertEqual(TrendsDateHelper.endOfWeek(for: expectedStart ?? date, calendar: calendar), expectedEnd)
    }

    func testWeekLabelSameYearUsesShortFormat() {
        let start = makeDate(year: 2025, month: 1, day: 5)
        let end = makeDate(year: 2025, month: 1, day: 11)

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.ReferenceType.default

        let expected = "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        XCTAssertEqual(TrendsDateHelper.weekLabel(start: start, end: end, calendar: calendar), expected)
    }

    func testWeekLabelCrossYearIncludesYear() {
        let start = makeDate(year: 2024, month: 12, day: 29)
        let end = makeDate(year: 2025, month: 1, day: 4)

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.ReferenceType.default

        let expected = "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        XCTAssertEqual(TrendsDateHelper.weekLabel(start: start, end: end, calendar: calendar), expected)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
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
