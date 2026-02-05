import Foundation
import SwiftData
import XCTest
@testable import marble

class MarbleTestCase: XCTestCase {
    enum FixtureMode {
        case empty
        case populated
    }

    static let fixedNow: Date = ISO8601DateFormatter().date(from: "2025-01-15T12:00:00Z")!
    static let stableCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    var now: Date { Self.fixedNow }

    private var originalTimeZone: TimeZone?
    private var originalDayLocale: Locale?
    private var originalDayTimeZone: TimeZone?

    override func setUp() {
        super.setUp()
        TestHooks.overrideNow = now

        originalTimeZone = TimeZone.ReferenceType.default
        if let gmt = TimeZone(secondsFromGMT: 0) {
            TimeZone.ReferenceType.default = gmt
        }

        originalDayLocale = Formatters.day.locale
        originalDayTimeZone = Formatters.day.timeZone
        Formatters.day.locale = Locale(identifier: "en_US_POSIX")
        Formatters.day.timeZone = TimeZone(secondsFromGMT: 0)
    }

    override func tearDown() {
        TestHooks.overrideNow = nil
        if let originalTimeZone {
            TimeZone.ReferenceType.default = originalTimeZone
        }
        if let originalDayLocale {
            Formatters.day.locale = originalDayLocale
        }
        if let originalDayTimeZone {
            Formatters.day.timeZone = originalDayTimeZone
        }
        super.tearDown()
    }

    func makeInMemoryContainer() -> ModelContainer {
        PersistenceController.makeContainer(useInMemory: true)
    }

    func makeInMemoryContext() -> ModelContext {
        ModelContext(makeInMemoryContainer())
    }

    func seedFixtures(mode: FixtureMode, in context: ModelContext, now: Date? = nil) {
        let resolvedNow = now ?? self.now
        switch mode {
        case .empty:
            TestFixtures.seedEmpty(in: context, now: resolvedNow)
        case .populated:
            TestFixtures.seed(in: context, now: resolvedNow)
        }
        try? context.save()
    }
}
