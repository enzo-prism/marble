import XCTest
@testable import marble

final class CalendarDayKeyTests: XCTestCase {
    func testDateComponentsWithMetadataStillResolveToSameKey() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let date = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2025,
            month: 3,
            day: 22,
            hour: 10,
            minute: 15
        ))!

        let storedKey = CalendarDayKey(date: date, calendar: calendar)
        var uiCalendarComponents = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2025,
            month: 3,
            day: 22
        )
        uiCalendarComponents.isLeapMonth = false

        XCTAssertEqual(CalendarDayKey(dateComponents: uiCalendarComponents), storedKey)
    }

    func testSameDayEntriesCollapseToSingleKey() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let morning = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2025,
            month: 3,
            day: 22,
            hour: 8
        ))!
        let evening = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2025,
            month: 3,
            day: 22,
            hour: 19
        ))!

        let keys = Set([
            CalendarDayKey(date: morning, calendar: calendar),
            CalendarDayKey(date: evening, calendar: calendar)
        ])

        XCTAssertEqual(keys.count, 1)
    }

    func testMissingDayPartsReturnNil() {
        XCTAssertNil(CalendarDayKey(dateComponents: DateComponents(year: 2025, month: 3)))
    }
}
