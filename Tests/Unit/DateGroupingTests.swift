import XCTest
@testable import marble

final class DateGroupingTests: MarbleTestCase {
    private let calendar = MarbleTestCase.stableCalendar

    func testTodayLabel() {
        let label = DateHelper.dayLabel(for: now, now: now, calendar: calendar)
        XCTAssertEqual(label, "Today")
    }

    func testYesterdayLabel() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let label = DateHelper.dayLabel(for: yesterday, now: now, calendar: calendar)
        XCTAssertEqual(label, "Yesterday")
    }

    func testOlderDateLabel() {
        let older = calendar.date(byAdding: .day, value: -5, to: now)!
        let label = DateHelper.dayLabel(for: older, now: now, calendar: calendar)
        XCTAssertEqual(label, Formatters.day.string(from: older))
    }
}
