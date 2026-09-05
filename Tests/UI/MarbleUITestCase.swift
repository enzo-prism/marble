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

enum MarbleTab: String, CaseIterable {
    case addWorkout = "Add Workout"
    case journal = "Journal"
    case calendar = "Calendar"
    case supplements = "Supplements"
    case trends = "Trends"

    var identifier: String {
        self == .addWorkout ? "Tab.Add" : "Tab.\(rawValue)"
    }

    /// Visible tab-bar label after the Add / Log / Progress IA.
    /// Calendar and Supplements are Log modes, not tab-bar items.
    var tabBarLabel: String {
        switch self {
        case .journal: return "Log"
        case .addWorkout: return "Add"
        case .trends: return "Progress"
        case .calendar, .supplements: return rawValue
        }
    }

}

class MarbleUITestCase: XCTestCase {
    var app: XCUIApplication!
    private let draftNamespace = UUID().uuidString

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        // `hasSucceeded` is still false while tearDown is running, even for a
        // passing test, which used to attach a full failure hierarchy to every
        // App Store capture. Failure count is already final at this point.
        if let run = testRun, run.failureCount > 0 {
            attachFailureArtifacts()
        }
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
        calendarTestDay: String? = nil,
        notificationAuthorization: String? = nil,
        accessibilityAudit: Bool = false,
        extraEnvironment: [String: String] = [:]
    ) {
        if app != nil {
            app.terminate()
        }
        app = XCUIApplication()
        app.launchEnvironment["MARBLE_UI_TESTING"] = "1"
        app.launchEnvironment["MARBLE_DRAFT_NAMESPACE"] = draftNamespace
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
        if accessibilityAudit {
            app.launchEnvironment["MARBLE_A11Y_AUDIT"] = "1"
        }
        if let calendarTestDay {
            app.launchEnvironment["MARBLE_TEST_CALENDAR_DAY"] = calendarTestDay
        }
        if let notificationAuthorization {
            app.launchEnvironment["MARBLE_NOTIFICATION_AUTHORIZATION"] = notificationAuthorization
        }
        if let contentSizeCategory {
            app.launchEnvironment["MARBLE_FORCE_DYNAMIC_TYPE"] = contentSizeCategory
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSizeCategory]
        }
        for (key, value) in extraEnvironment {
            app.launchEnvironment[key] = value
        }
        app.launch()
    }

    func navigateToTab(_ tab: MarbleTab) {
        switch tab {
        case .journal:
            tapTabBarItem(.journal)
            if app.buttons["Log.Mode.Menu"].waitForExistence(timeout: 4) {
                forceTap(app.buttons["Log.Mode.Menu"])
            }
            let setsMode = app.descendants(matching: .any)
                .matching(identifier: "Log.Mode.Sets")
                .firstMatch
            if setsMode.waitForExistence(timeout: 6) {
                setsMode.tap()
                return
            }
            let labeled = app.segmentedControls.buttons["Sets"]
            if labeled.waitForExistence(timeout: 4) {
                labeled.tap()
            }
        case .calendar, .supplements:
            tapTabBarItem(.journal)
            if app.buttons["Log.Mode.Menu"].waitForExistence(timeout: 4) {
                forceTap(app.buttons["Log.Mode.Menu"])
            }
            let modeIdentifier = tab == .calendar ? "Tab.Calendar" : "Tab.Supplements"
            let mode = app.descendants(matching: .any).matching(identifier: modeIdentifier).firstMatch
            if mode.waitForExistence(timeout: 6) {
                forceTap(mode)
                return
            }
            let labeled = app.segmentedControls.buttons[tab.rawValue]
            if labeled.waitForExistence(timeout: 4) {
                forceTap(labeled)
            }
        default:
            tapTabBarItem(tab)
        }
    }

    func tapTabBarItem(_ tab: MarbleTab) {
        let identified = app.buttons.matching(identifier: tab.identifier).firstMatch
        if identified.waitForExistence(timeout: 4) {
            forceTap(identified)
            return
        }
        let tabLabel = NSPredicate(
            format: "identifier == %@ OR identifier == %@ OR label == %@ OR label == %@",
            tab.identifier,
            tab.rawValue,
            tab.rawValue,
            tab.tabBarLabel
        )
        let fallback = app.tabBars.buttons.matching(tabLabel).firstMatch
        if fallback.waitForExistence(timeout: 4) {
            forceTap(fallback)
        }
    }

    func revealDetailedTrends(file: StaticString = #file, line: UInt = #line) {
        let toggle = waitForIdentifier("Trends.Details.Toggle", timeout: 8, file: file, line: line)
        forceTap(toggle, file: file, line: line)
    }

    func forceTap(_ element: XCUIElement, timeout: TimeInterval = 5, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), file: file, line: line)
        // iOS 26.5 can accept an XCUIElement tap without dispatching the SwiftUI
        // action, even when the element reports itself hittable. Use a real
        // coordinate, clamped to the portion not covered by navigation/tab
        // chrome, instead of trusting a stale accessibility activation point.
        tapVisible(element)
    }

    func tapVisible(
        _ element: XCUIElement,
        normalizedOffset: CGVector = CGVector(dx: 0.5, dy: 0.5)
    ) {
        let elementFrame = element.frame
        let visibleFrame = unobscuredFrame().intersection(elementFrame)
        guard !visibleFrame.isNull, !visibleFrame.isEmpty,
              elementFrame.width > 0, elementFrame.height > 0 else {
            element.coordinate(withNormalizedOffset: normalizedOffset).tap()
            return
        }

        let desiredX = elementFrame.minX + elementFrame.width * normalizedOffset.dx
        let desiredY = elementFrame.minY + elementFrame.height * normalizedOffset.dy
        let targetX = min(max(desiredX, visibleFrame.minX + 1), visibleFrame.maxX - 1)
        let targetY = min(max(desiredY, visibleFrame.minY + 1), visibleFrame.maxY - 1)
        let safeOffset = CGVector(
            dx: (targetX - elementFrame.minX) / elementFrame.width,
            dy: (targetY - elementFrame.minY) / elementFrame.height
        )
        element.coordinate(withNormalizedOffset: safeOffset).tap()
    }

    func takeScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func openAddToolbarAction(_ identifier: String) {
        forceTap(waitForIdentifier("Workout.More", timeout: 8))
        forceTap(waitForIdentifier(identifier, timeout: 8))
    }

    func waitFor(_ element: XCUIElement, timeout: TimeInterval = 5, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), file: file, line: line)
    }

    func scrollToElement(_ element: XCUIElement, in container: XCUIElement, maxSwipes: Int = 8) {
        func isMeaningfullyVisible() -> Bool {
            guard element.exists, container.exists else { return false }
            let visibleFrame = unobscuredFrame(in: container)
            let intersection = visibleFrame.intersection(element.frame)
            guard !intersection.isNull, !intersection.isEmpty else { return false }
            let requiredHeight = min(32, element.frame.height * 0.33)
            return intersection.width >= min(32, element.frame.width * 0.33)
                && intersection.height >= requiredHeight
        }

        if isMeaningfullyVisible() { return }
        for _ in 0..<maxSwipes {
            // Lazy List rows do not enter the accessibility hierarchy until
            // they approach the viewport. Scroll forward without asking for a
            // nonexistent frame, which itself makes XCUITest fail the case.
            guard element.exists else {
                if container.isHittable {
                    container.swipeUp()
                } else {
                    app.swipeUp()
                }
                continue
            }

            let previousFrame = element.frame
            let visibleFrame = unobscuredFrame(in: container.exists ? container : nil)

            // A partially visible element already has a deterministic safe
            // coordinate. Do not reverse full-screen swipes trying to achieve
            // perfect containment; that can oscillate around fixed chrome.
            let intersection = visibleFrame.intersection(element.frame)
            if !intersection.isNull, intersection.width >= 2, intersection.height >= 2 {
                return
            }

            if container.isHittable {
                if element.frame.maxY <= visibleFrame.minY {
                    container.swipeDown()
                } else if element.frame.minY >= visibleFrame.maxY {
                    container.swipeUp()
                } else if element.frame.minY < visibleFrame.minY {
                    container.swipeDown()
                } else {
                    container.swipeUp()
                }
            } else {
                if element.frame.maxY <= visibleFrame.minY {
                    app.swipeDown()
                } else if element.frame.minY >= visibleFrame.maxY {
                    app.swipeUp()
                } else if element.frame.minY < visibleFrame.minY {
                    app.swipeDown()
                } else {
                    app.swipeUp()
                }
            }
            if isMeaningfullyVisible() {
                return
            }
            if element.exists, abs(element.frame.minY - previousFrame.minY) < 1 {
                return
            }
        }
    }

    private func unobscuredFrame(in container: XCUIElement? = nil) -> CGRect {
        var frame = container?.frame.intersection(app.frame) ?? app.frame

        let navigationBar = app.navigationBars.firstMatch
        if navigationBar.exists, navigationBar.frame.intersects(frame) {
            let top = max(frame.minY, navigationBar.frame.maxY + 8)
            frame = CGRect(x: frame.minX, y: top, width: frame.width, height: max(0, frame.maxY - top))
        }

        let tabBar = app.tabBars.firstMatch
        if tabBar.exists, tabBar.frame.intersects(frame) {
            let bottom = min(frame.maxY, tabBar.frame.minY - 8)
            frame = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: max(0, bottom - frame.minY))
        }

        return frame.insetBy(dx: 0, dy: 8)
    }

    func dismissKeyboardIfPresent() {
        guard app.keyboards.count > 0 else { return }
        if app.descendants(matching: .any).matching(identifier: "TextEntry.Keyboard.Done").firstMatch.exists {
            app.descendants(matching: .any).matching(identifier: "TextEntry.Keyboard.Done").firstMatch.tap()
            return
        }
        if app.buttons["Keyboard.Done"].exists {
            app.buttons["Keyboard.Done"].tap()
            return
        }
        if app.buttons["Done"].exists {
            app.buttons["Done"].tap()
            return
        }
        if app.buttons["Keyboard.Save"].exists {
            app.buttons["Keyboard.Save"].tap()
            return
        }
        if app.keyboards.buttons["Return"].exists {
            app.keyboards.buttons["Return"].tap()
            return
        }
        let navBar = app.navigationBars.element(boundBy: 0)
        if navBar.exists {
            navBar.tap()
            return
        }
        app.tap()
    }

    /// Bottom accessories intentionally sit above and can overlap the tab bar's
    /// accessibility frame. Tap their own visual center instead of routing
    /// through `forceTap`, which clips coordinates to the content area.
    func tapBottomAccessory(
        _ element: XCUIElement,
        timeout: TimeInterval = 8,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        waitFor(element, timeout: timeout, file: file, line: line)
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
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

    /// `@MainActor` on the closure, and `assumeIsolated` inside XCTest's
    /// nonisolated activity block: XCUITest calls all happen on the main thread,
    /// but `runActivity`'s closure is not annotated, so under the Swift 6
    /// language mode passing a main-actor closure straight in reads as sending it.
    func step(_ name: String, _ block: @MainActor () throws -> Void) rethrows {
        try XCTContext.runActivity(named: name) { _ in
            try MainActor.assumeIsolated { try block() }
        }
    }

    @discardableResult
    func waitForIdentifier(_ identifier: String, timeout: TimeInterval = 5, file: StaticString = #file, line: UInt = #line) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), file: file, line: line)
        return element
    }

    func addSetListContainer(timeout: TimeInterval = 6) -> XCUIElement {
        let list = app.descendants(matching: .any).matching(identifier: "AddSet.List").firstMatch
        if list.waitForExistence(timeout: timeout) {
            return list
        }
        let table = app.tables.firstMatch
        if table.exists {
            return table
        }
        let collection = app.collectionViews.firstMatch
        if collection.exists {
            return collection
        }
        return app
    }

    func revealAddSetSaveButton(
        maxSwipes: Int = 6,
        timeout: TimeInterval = 2,
        file: StaticString = #file,
        line: UInt = #line
    ) -> XCUIElement {
        let navSaveButton = app.navigationBars.buttons["AddSet.Save"]
        if navSaveButton.waitForExistence(timeout: timeout) {
            return navSaveButton
        }

        let saveButton = app.descendants(matching: .any).matching(identifier: "AddSet.SaveAndNext").firstMatch
        if saveButton.exists {
            return saveButton
        }
        let container = addSetListContainer(timeout: timeout)
        for _ in 0..<maxSwipes {
            if container.isHittable {
                container.swipeUp()
            } else {
                app.swipeUp()
            }
            if saveButton.exists {
                break
            }
        }
        XCTAssertTrue(saveButton.waitForExistence(timeout: timeout), file: file, line: line)
        return saveButton
    }

    // `nonisolated`: `NSPredicate` is not `Sendable`, so building it here and
    // handing it to XCUITest's nonisolated query API from a main-actor context
    // would be sending it across isolation. Keeping the whole helper nonisolated
    // keeps the predicate on one side of that boundary.
    nonisolated func setRows(in list: XCUIElement) -> XCUIElementQuery {
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
        return app.descendants(matching: .any).matching(predicate)
    }

    func supplementRow(named name: String, in list: XCUIElement) -> XCUIElement {
        let sanitized = name.replacingOccurrences(of: " ", with: "")
        return list.descendants(matching: .any).matching(identifier: "SupplementRow.\(sanitized)").firstMatch
    }

    func clearAndType(_ element: XCUIElement, text: String) {
        element.tap()
        if let value = element.value as? String, !value.isEmpty {
            // Rounded SwiftUI text-field bounds include a non-editable border.
            // The former 98% edge tap could hit that border and dismiss focus
            // immediately before typing (observed in the live PR weight flow).
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.5)).tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                          "Editing an existing value must keep the keyboard open")
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count + 2)
            element.typeText(deleteString)
        }
        element.typeText(text)
    }

    func setSliderValue(_ identifier: String, value: Double, range: ClosedRange<Double>, file: StaticString = #file, line: UInt = #line) {
        let normalized = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        let clamped = min(max(normalized, 0), 1)

        let slider = app.sliders[identifier]
        if slider.waitForExistence(timeout: 5) {
            if !slider.isHittable {
                app.swipeUp()
            }
            slider.adjust(toNormalizedSliderPosition: clamped)
            return
        }

        let fallback = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(fallback.waitForExistence(timeout: 5), file: file, line: line)
        if !fallback.isHittable {
            app.swipeUp()
        }
        let start = fallback.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        let end = fallback.coordinate(withNormalizedOffset: CGVector(dx: min(max(clamped, 0.05), 0.95), dy: 0.5))
        start.press(forDuration: 0.01, thenDragTo: end)
    }

    func textInput(_ identifier: String) -> XCUIElement {
        let field = app.textFields[identifier]
        if field.exists {
            return field
        }
        let textView = app.textViews[identifier]
        if textView.exists {
            return textView
        }
        return app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Returns an Add Set text input after materializing it in the lazy form.
    /// Cards above the metrics can push the field below the visible List even
    /// though the selected exercise has already changed.
    func revealAddSetTextInput(
        _ identifier: String,
        timeout: TimeInterval = 6,
        file: StaticString = #file,
        line: UInt = #line
    ) -> XCUIElement {
        let list = addSetListContainer()

        // Re-resolve the query after every swipe. Lazy List rows can leave the
        // accessibility hierarchy while scrolling, and retaining the original
        // generic descendant query can oscillate past a newly materialized
        // TextField when cards above the metrics change the row's position.
        for scrollsForward in [true, false] {
            for _ in 0..<10 {
                let candidate = textInput(identifier)
                if candidate.exists, candidate.isHittable {
                    return candidate
                }

                if candidate.exists {
                    // Once the lazy row materializes, avoid a full reverse
                    // swipe. The metrics field commonly lands just beneath
                    // fixed navigation chrome, where a full swipe down sends
                    // it back out of the lazy hierarchy and causes an
                    // up/down oscillation. Nudge the content toward the
                    // unobscured center instead, then re-resolve the field.
                    let visibleFrame = unobscuredFrame(in: list.exists ? list : nil)
                    let isAboveViewport = candidate.frame.midY < visibleFrame.midY
                    let start = list.coordinate(
                        withNormalizedOffset: CGVector(dx: 0.5, dy: isAboveViewport ? 0.35 : 0.65)
                    )
                    let end = list.coordinate(
                        withNormalizedOffset: CGVector(dx: 0.5, dy: isAboveViewport ? 0.55 : 0.45)
                    )
                    start.press(forDuration: 0.01, thenDragTo: end)
                } else if list.isHittable {
                    if scrollsForward { list.swipeUp() } else { list.swipeDown() }
                } else {
                    if scrollsForward { app.swipeUp() } else { app.swipeDown() }
                }
            }
        }

        let field = textInput(identifier)
        XCTAssertTrue(field.waitForExistence(timeout: timeout), file: file, line: line)
        XCTAssertTrue(field.isHittable, file: file, line: line)
        return field
    }

    func selectExercise(identifier: String) {
        let picker = app.buttons["AddSet.ExercisePicker"]
        waitFor(picker)
        forceTap(picker)

        let list = waitForIdentifier("ExercisePicker.List", timeout: 8)
        let row = app.buttons.matching(identifier: "ExercisePicker.Row.\(identifier)").firstMatch
        if !row.waitForExistence(timeout: 2) {
            let searchField = app.searchFields.firstMatch
            if searchField.waitForExistence(timeout: 2) {
                searchField.tap()
                searchField.typeText(exerciseSearchQuery(for: identifier))
            }
        }
        waitFor(row, timeout: 8)
        if !row.isHittable {
            scrollToElement(row, in: list, maxSwipes: 12)
        }
        forceTap(row)
        let exercisesNav = app.navigationBars["Exercises"]
        if exercisesNav.waitForExistence(timeout: 2) {
            let backButton = exercisesNav.buttons.element(boundBy: 0)
            if backButton.exists {
                backButton.tap()
            }
        }
        waitFor(app.navigationBars["Log Set"], timeout: 8)
    }

    private func exerciseSearchQuery(for identifier: String) -> String {
        identifier.replacingOccurrences(
            of: "([a-z])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        )
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
        let calendar = app.otherElements["Calendar.View"]
        if calendar.waitForExistence(timeout: 4) {
            let predicate = NSPredicate(format: "label == %@ OR label BEGINSWITH %@ OR label CONTAINS %@", day, "\(day)", day)
            let dayElement = calendar.descendants(matching: .any)
                .matching(predicate)
                .firstMatch
            if dayElement.waitForExistence(timeout: 4) {
                dayElement.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                return
            }
        }

        let testPopulated = app.buttons["Calendar.TestOpenPopulated"]
        if day == "15", testPopulated.exists {
            forceTap(testPopulated)
            return
        }
        let testEmpty = app.buttons["Calendar.TestOpenEmpty"]
        if day == "1", testEmpty.exists {
            forceTap(testEmpty)
        }
    }

    static func fixtureNowISO8601(hour: Int, minute: Int = 0) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 15
        components.hour = hour
        components.minute = minute
        components.second = 0
        let date = calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static let fixedNowISO8601 = fixtureNowISO8601(hour: 12)

    private func attachFailureArtifacts() {
        guard let app else { return }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Failure Screenshot"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Failure Hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
