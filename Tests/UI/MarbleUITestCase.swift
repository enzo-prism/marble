import Foundation
import XCTest

enum MarbleAppearance {
    case light
    case dark

    var envValue: String {
        switch self {
        case .light:
            return "light"
        case .dark:
            return "dark"
        }
    }
}

enum MarbleTab: String {
    case journal = "Journal"
    case calendar = "Calendar"
    case split = "Split"
    case supplements = "Supplements"
    case trends = "Trends"

    var identifier: String {
        "Tab.\(rawValue)"
    }
}

class MarbleUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    func launchApp(
        appearance: MarbleAppearance = .light,
        contentSizeCategory: String? = nil,
        fixtureMode: String = "populated",
        nowISO8601: String = MarbleUITestCase.fixedNowISO8601,
        resetDB: Bool = true,
        forceReduceTransparency: Bool = false,
        calendarTestDay: String? = nil
    ) {
        if app != nil {
            app.terminate()
        }
        app = XCUIApplication()
        app.launchEnvironment["MARBLE_UI_TESTING"] = "1"
        app.launchEnvironment["MARBLE_DISABLE_ANIMATIONS"] = "1"
        if resetDB {
            app.launchEnvironment["MARBLE_RESET_DB"] = "1"
        }
        app.launchEnvironment["MARBLE_NOW_ISO8601"] = nowISO8601
        app.launchEnvironment["MARBLE_FIXTURE_MODE"] = fixtureMode
        app.launchEnvironment["MARBLE_FORCE_COLOR_SCHEME"] = appearance.envValue
        if forceReduceTransparency {
            app.launchEnvironment["MARBLE_FORCE_REDUCE_TRANSPARENCY"] = "1"
        }
        if let calendarTestDay {
            app.launchEnvironment["MARBLE_TEST_CALENDAR_DAY"] = calendarTestDay
        }
        if let contentSizeCategory {
            app.launchEnvironment["MARBLE_FORCE_DYNAMIC_TYPE"] = contentSizeCategory
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSizeCategory]
        }
        app.launch()
    }

    func navigateToTab(_ tab: MarbleTab) {
        let fallback = app.tabBars.buttons[tab.rawValue]
        if fallback.waitForExistence(timeout: 4) {
            forceTap(fallback)
            return
        }
        let identified = app.buttons[tab.identifier]
        if identified.waitForExistence(timeout: 4) {
            forceTap(identified)
            return
        }
    }

    func forceTap(_ element: XCUIElement, timeout: TimeInterval = 5, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), file: file, line: line)
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    func takeScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func waitFor(_ element: XCUIElement, timeout: TimeInterval = 5, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), file: file, line: line)
    }

    func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 5, file: StaticString = #file, line: UInt = #line) {
        let start = Date()
        while element.exists && element.isHittable && Date().timeIntervalSince(start) < timeout {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        if element.exists && element.isHittable {
            XCTFail("Element still hittable after \(timeout)s", file: file, line: line)
        }
    }

    @discardableResult
    func waitForIdentifier(_ identifier: String, timeout: TimeInterval = 5, file: StaticString = #file, line: UInt = #line) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), file: file, line: line)
        return element
    }

    func setRows(in list: XCUIElement) -> XCUIElementQuery {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "SetRow.")
        let scoped = list.descendants(matching: .any).matching(predicate)
        if scoped.count > 0 {
            return scoped
        }
        let global = app.descendants(matching: .any).matching(predicate)
        if global.count > 0 {
            return global
        }
        let buttons = list.descendants(matching: .button).matching(predicate)
        if buttons.count > 0 {
            return buttons
        }
        let cellsById = list.cells.matching(predicate)
        if cellsById.count > 0 {
            return cellsById
        }
        let cells = list.cells
        if cells.count > 0 {
            return cells
        }
        return app.descendants(matching: .any).matching(predicate)
    }

    func supplementRow(named name: String, in list: XCUIElement) -> XCUIElement {
        let sanitized = name.replacingOccurrences(of: " ", with: "")
        return list.descendants(matching: .any).matching(identifier: "SupplementRow.\(sanitized)").firstMatch
    }

    func clearAndType(_ element: XCUIElement, text: String) {
        element.tap()
        if let value = element.value as? String, !value.isEmpty {
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)
            element.typeText(deleteString)
        }
        element.typeText(text)
    }

    func textInput(_ identifier: String) -> XCUIElement {
        let field = app.textFields[identifier]
        if field.exists {
            return field
        }
        return app.textViews[identifier]
    }

    func selectExercise(identifier: String) {
        let picker = app.buttons["AddSet.ExercisePicker"]
        waitFor(picker)
        picker.tap()

        let row = app.buttons.matching(identifier: "ExercisePicker.Row.\(identifier)").firstMatch
        waitFor(row)
        row.tap()
    }

    func openAddSet() {
        let quickLog = app.buttons["QuickLog.Button"]
        waitFor(quickLog)
        quickLog.tap()
        waitFor(app.navigationBars["Log Set"])
    }

    func dismissSheet() {
        if app.navigationBars["Log Set"].exists {
            app.navigationBars["Log Set"].swipeDown()
            if app.navigationBars["Log Set"].exists {
                app.swipeDown()
            }
            return
        }
        if app.navigationBars["Summary"].exists {
            app.navigationBars["Summary"].swipeDown()
            if app.navigationBars["Summary"].exists {
                app.swipeDown()
            }
            return
        }
        app.swipeDown()
    }

    func selectCalendarDay(_ day: String) {
        let testPopulated = app.buttons["Calendar.TestOpenPopulated"]
        if day == "15", testPopulated.exists {
            forceTap(testPopulated)
            return
        }
        let testEmpty = app.buttons["Calendar.TestOpenEmpty"]
        if day == "1", testEmpty.exists {
            forceTap(testEmpty)
            return
        }

        let calendar = app.otherElements["Calendar.View"]
        waitFor(calendar)
        let predicate = NSPredicate(format: "label == %@ OR label BEGINSWITH %@ OR label CONTAINS %@", day, "\(day)", day)
        let dayElement = calendar.descendants(matching: .any)
            .matching(predicate)
            .firstMatch
        waitFor(dayElement, timeout: 8)
        dayElement.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    static let fixedNowISO8601: String = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 15
        components.hour = 12
        components.minute = 0
        components.second = 0
        let date = calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }()
}
