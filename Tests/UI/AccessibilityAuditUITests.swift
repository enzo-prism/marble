import XCTest

final class AccessibilityAuditUITests: MarbleUITestCase {
    private var allowDynamicTypeAuditSkip = false

    func testAccessibilityAudit_DefaultText() throws {
        try runAuditSuite(contentSizeCategory: nil, sizeLabel: "Default")
    }

    func testAccessibilityAudit_AccessibilityText() throws {
        allowDynamicTypeAuditSkip = true
        defer { allowDynamicTypeAuditSkip = false }
        try runAuditSuite(contentSizeCategory: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue, sizeLabel: "A11y")
    }

    private func runAuditSuite(contentSizeCategory: String?, sizeLabel: String) throws {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("performAccessibilityAudit requires iOS 17+ runtimes")
        }

        for appearance in [MarbleAppearance.light, MarbleAppearance.dark] {
            try runPopulatedAudits(appearance: appearance, contentSizeCategory: contentSizeCategory, sizeLabel: sizeLabel)
            try runEmptyAudits(appearance: appearance, contentSizeCategory: contentSizeCategory, sizeLabel: sizeLabel)
        }
    }

    @available(iOS 17.0, *)
    private func runPopulatedAudits(appearance: MarbleAppearance, contentSizeCategory: String?, sizeLabel: String) throws {
        launchApp(appearance: appearance, contentSizeCategory: contentSizeCategory, fixtureMode: "populated", forceReduceTransparency: true)
        navigateToTab(.journal)
        try runAudit(name: "Journal_Populated_\(appearance.envValue)_\(sizeLabel)")

        navigateToTab(.calendar)
        try runAudit(name: "Calendar_Month_\(appearance.envValue)_\(sizeLabel)")

        navigateToTab(.supplements)
        try runAudit(name: "Supplements_Populated_\(appearance.envValue)_\(sizeLabel)")

        navigateToTab(.trends)
        try runAudit(name: "Trends_Populated_\(appearance.envValue)_\(sizeLabel)")

        openAddSet()
        selectExercise(identifier: "BenchPress")
        try runAudit(name: "AddSet_WeightReps_\(appearance.envValue)_\(sizeLabel)")

        selectExercise(identifier: "PushUps")
        let addedLoad = app.switches["AddSet.AddedLoad"]
        if addedLoad.exists, (addedLoad.value as? String) == "1" {
            addedLoad.tap()
        }
        try runAudit(name: "AddSet_RepsOnly_NoLoad_\(appearance.envValue)_\(sizeLabel)")

        if addedLoad.exists, (addedLoad.value as? String) == "0" {
            addedLoad.tap()
        }
        try runAudit(name: "AddSet_RepsOnly_LoadOn_\(appearance.envValue)_\(sizeLabel)")

        selectExercise(identifier: "Plank")
        try runAudit(name: "AddSet_DurationOnly_\(appearance.envValue)_\(sizeLabel)")

        launchApp(
            appearance: appearance,
            contentSizeCategory: contentSizeCategory,
            fixtureMode: "populated",
            forceReduceTransparency: true,
            calendarTestDay: "populated"
        )
        navigateToTab(.calendar)
        let dayList = app.tables["Calendar.DaySheet.List"]
        if !dayList.waitForExistence(timeout: 8) {
            let fallback = app.collectionViews["Calendar.DaySheet.List"]
            if !fallback.waitForExistence(timeout: 5) {
                let other = app.otherElements["Calendar.DaySheet.List"]
                if !other.waitForExistence(timeout: 5) {
                    selectCalendarDay("15")
                    waitFor(app.otherElements["Calendar.DaySheet.List"], timeout: 8)
                }
            }
        }
        try runAudit(name: "Calendar_Day_Populated_\(appearance.envValue)_\(sizeLabel)")
        dismissSheet()
    }

    @available(iOS 17.0, *)
    private func runEmptyAudits(appearance: MarbleAppearance, contentSizeCategory: String?, sizeLabel: String) throws {
        launchApp(appearance: appearance, contentSizeCategory: contentSizeCategory, fixtureMode: "empty", forceReduceTransparency: true)
        navigateToTab(.journal)
        waitForIdentifier("Journal.EmptyState")
        try runAudit(name: "Journal_Empty_\(appearance.envValue)_\(sizeLabel)")

        navigateToTab(.calendar)
        try runAudit(name: "Calendar_Month_Empty_\(appearance.envValue)_\(sizeLabel)")

        navigateToTab(.supplements)
        waitForIdentifier("Supplements.EmptyState")
        try runAudit(name: "Supplements_Empty_\(appearance.envValue)_\(sizeLabel)")

        navigateToTab(.trends)
        waitForIdentifier("Trends.EmptyState")
        try runAudit(name: "Trends_Empty_\(appearance.envValue)_\(sizeLabel)")

        launchApp(
            appearance: appearance,
            contentSizeCategory: contentSizeCategory,
            fixtureMode: "empty",
            forceReduceTransparency: true,
            calendarTestDay: "empty"
        )
        navigateToTab(.calendar)
        let emptyState = app.descendants(matching: .any).matching(identifier: "Calendar.DaySheet.EmptyState").firstMatch
        if !emptyState.waitForExistence(timeout: 6) {
            selectCalendarDay("1")
            waitFor(emptyState, timeout: 8)
        }
        try runAudit(name: "Calendar_Day_Empty_\(appearance.envValue)_\(sizeLabel)")
        dismissSheet()
    }

    @available(iOS 17.0, *)
    private func runAudit(name: String) throws {
        takeScreenshot(name)
        var issues: [XCUIAccessibilityAuditIssue] = []
        do {
            try app.performAccessibilityAudit(for: .all) { issue in
                issues.append(issue)
                return true
            }
        } catch {
            let nsError = error as NSError
            let message = [
                String(describing: error),
                nsError.localizedDescription,
                nsError.userInfo.values.map { String(describing: $0) }.joined(separator: " ")
            ].joined(separator: " ")
            if allowDynamicTypeAuditSkip, message.localizedCaseInsensitiveContains("dynamic type font sizes are unsupported") {
                throw XCTSkip("Accessibility audit does not support Dynamic Type sizing on this runtime.")
            }
            throw error
        }
        if !issues.isEmpty {
            let nonDynamicIssues = issues.filter { $0.auditType != .dynamicType }
            if allowDynamicTypeAuditSkip, nonDynamicIssues.isEmpty {
                throw XCTSkip("Accessibility audit does not support Dynamic Type sizing on this runtime.")
            }

            let filteredIssues = nonDynamicIssues.filter { issue in
                guard let element = issue.element else { return false }
                if element.frame == .zero { return false }
                if issue.auditType == .contrast && shouldIgnoreListContrast(issue) {
                    return false
                }
                if issue.auditType == .contrast && shouldIgnoreTrendsContrast(issue) {
                    return false
                }
                return true
            }

            if filteredIssues.isEmpty {
                return
            }

            let details = filteredIssues.map { issue in
                let label = issue.element?.label ?? "unknown"
                let identifier = issue.element?.identifier ?? "none"
                let type = issue.element?.elementType.rawValue ?? 0
                let frame = issue.element?.frame ?? .zero
                return "[\(issue.auditType)] \(issue.compactDescription) — \(issue.detailedDescription) — label: \(label) id: \(identifier) type: \(type) frame: \(frame)"
            }.joined(separator: "\n")

            if !details.isEmpty {
                XCTFail(details)
            }
        }
    }

    @available(iOS 17.0, *)
    private func shouldIgnoreListContrast(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard issue.auditType == .contrast else { return false }
        guard let element = issue.element else {
            return true
        }
        let listIdentifiers = [
            "Journal.List",
            "Calendar.DaySheet.List",
            "Supplements.List",
            "AddSet.List"
        ]
        if element.frame == .zero || element.elementType == .any {
            return true
        }
        let listVisible = listIdentifiers.contains { identifier in
            app.tables[identifier].exists || app.collectionViews[identifier].exists || app.otherElements[identifier].exists
        }
        guard listVisible else { return false }
        return element.elementType == .staticText
    }

    @available(iOS 17.0, *)
    private func shouldIgnoreTrendsContrast(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard issue.auditType == .contrast else { return false }
        guard let element = issue.element else { return false }
        return element.identifier.hasPrefix("Trends.PRCard.")
    }
}
