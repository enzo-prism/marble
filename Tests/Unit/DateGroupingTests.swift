import XCTest
@testable import marble

final class DateGroupingTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    private let now = ISO8601DateFormatter().date(from: "2025-01-15T12:00:00Z")!

    override func setUp() {
        super.setUp()
        TestHooks.overrideNow = now
        Formatters.day.locale = Locale(identifier: "en_US_POSIX")
        Formatters.day.timeZone = TimeZone(secondsFromGMT: 0)
    }

    override func tearDown() {
        TestHooks.overrideNow = nil
        super.tearDown()
    }

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

