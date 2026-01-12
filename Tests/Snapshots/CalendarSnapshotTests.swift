import SwiftData
import XCTest
@testable import marble

final class CalendarSnapshotTests: SnapshotTestCase {
    func testCalendarMonthWithMarkers() {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)

        let view = CalendarView()
            .modelContainer(container)
            .environmentObject(QuickLogCoordinator())
            .environmentObject(TabSelection())
        assertSnapshot(view, named: "Calendar_MonthMarkers")
    }

    func testCalendarDaySheetWithEntries() throws {
        let container = SnapshotFixtures.makeContainer()
        let context = ModelContext(container)
        SnapshotFixtures.seedPopulated(in: context)

        let entries = try context.fetch(FetchDescriptor<SetEntry>())
        let todayEntries = entries.filter { Calendar.current.isDate($0.performedAt, inSameDayAs: SnapshotFixtures.now) }

        let view = DaySummarySheet(date: SnapshotFixtures.now, entries: todayEntries)
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(view, named: "Calendar_DaySheet_Populated")
    }

    func testCalendarDaySheetEmpty() {
        let emptyDate = Calendar.current.date(byAdding: .day, value: 5, to: SnapshotFixtures.now) ?? SnapshotFixtures.now
        let view = DaySummarySheet(date: emptyDate, entries: [])
            .environmentObject(QuickLogCoordinator())
        assertSnapshot(view, named: "Calendar_DaySheet_Empty")
    }
}
