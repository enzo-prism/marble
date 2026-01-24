import Foundation
import SwiftUI
import UIKit

enum AppEnvironment {
    static var now: Date { TestHooks.now }
}

enum TestHooks {
    enum FixtureMode: String {
        case populated
        case empty
    }

    static var overrideNow: Date?

    static let isUITesting: Bool = environmentFlag("MARBLE_UI_TESTING")
    static let disableAnimations: Bool = environmentFlag("MARBLE_DISABLE_ANIMATIONS") || isUITesting
    static let forcedColorScheme: ColorScheme? = TestHooks.parseColorScheme(environmentValue("MARBLE_FORCE_COLOR_SCHEME"))
    static let forcedDynamicType: ContentSizeCategory? = TestHooks.parseContentSize(environmentValue("MARBLE_FORCE_DYNAMIC_TYPE"))
    static let forceReduceTransparency: Bool = environmentFlag("MARBLE_FORCE_REDUCE_TRANSPARENCY")
    static let isAccessibilityAudit: Bool = environmentFlag("MARBLE_A11Y_AUDIT")
    static let fixtureMode: FixtureMode = FixtureMode(rawValue: (environmentValue("MARBLE_FIXTURE_MODE") ?? "populated").lowercased()) ?? .populated
    static let calendarTestDay: String? = environmentValue("MARBLE_TEST_CALENDAR_DAY")?.lowercased()

    static var now: Date {
        if let overrideNow { return overrideNow }
        if let envNow = environmentValue("MARBLE_NOW_ISO8601"), let date = parseISO8601(envNow) {
            return date
        }
        return Date()
    }

    static var resetDatabase: Bool {
        guard isUITesting || environmentFlag("MARBLE_RESET_DB") else { return false }
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static var useInMemoryStore: Bool {
        isUITesting
    }

    static func applyGlobalSettings() {
        if disableAnimations {
            UIView.setAnimationsEnabled(false)
        }
    }

    private static func environmentValue(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }

    private static func environmentFlag(_ key: String) -> Bool {
        environmentValue(key) == "1"
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        let fallback = ISO8601DateFormatter()
        return fallback.date(from: value)
    }

    private static func parseColorScheme(_ value: String?) -> ColorScheme? {
        switch value?.lowercased() {
        case "light":
            return .light
        case "dark":
            return .dark
        case "system", nil:
            return nil
        default:
            return nil
        }
    }

    private static func parseContentSize(_ value: String?) -> ContentSizeCategory? {
        guard let value else { return nil }
        switch value {
        case UIContentSizeCategory.extraSmall.rawValue:
            return .extraSmall
        case UIContentSizeCategory.small.rawValue:
            return .small
        case UIContentSizeCategory.medium.rawValue:
            return .medium
        case UIContentSizeCategory.large.rawValue:
            return .large
        case UIContentSizeCategory.extraLarge.rawValue:
            return .extraLarge
        case UIContentSizeCategory.extraExtraLarge.rawValue:
            return .extraExtraLarge
        case UIContentSizeCategory.extraExtraExtraLarge.rawValue:
            return .extraExtraExtraLarge
        case UIContentSizeCategory.accessibilityMedium.rawValue:
            return .accessibilityMedium
        case UIContentSizeCategory.accessibilityLarge.rawValue:
            return .accessibilityLarge
        case UIContentSizeCategory.accessibilityExtraLarge.rawValue:
            return .accessibilityExtraLarge
        case UIContentSizeCategory.accessibilityExtraExtraLarge.rawValue:
            return .accessibilityExtraExtraLarge
        case UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue:
            return .accessibilityExtraExtraExtraLarge
        default:
            return nil
        }
    }
}

extension View {
    func applyTestOverrides() -> some View {
        modifier(TestOverridesModifier(
            colorScheme: TestHooks.forcedColorScheme,
            sizeCategory: TestHooks.forcedDynamicType,
            disableAnimations: TestHooks.disableAnimations,
            reduceTransparency: TestHooks.forceReduceTransparency
        ))
    }
}

private struct TestOverridesModifier: ViewModifier {
    let colorScheme: ColorScheme?
    let sizeCategory: ContentSizeCategory?
    let disableAnimations: Bool
    let reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let base = content.preferredColorScheme(colorScheme)
        let transparencyAdjusted = reduceTransparency
            ? AnyView(base.environment(\.marbleReduceTransparencyOverride, true))
            : AnyView(base)
        if let sizeCategory {
            if disableAnimations {
                transparencyAdjusted
                    .environment(\.sizeCategory, sizeCategory)
                    .transaction { transaction in
                        transaction.disablesAnimations = true
                    }
            } else {
                transparencyAdjusted.environment(\.sizeCategory, sizeCategory)
            }
        } else {
            if disableAnimations {
                transparencyAdjusted.transaction { transaction in
                    transaction.disablesAnimations = true
                }
            } else {
                transparencyAdjusted
            }
        }
    }
}
