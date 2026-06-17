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
    /// Marketing capture mode: seeds the rich `seedShowcase` dataset into an in-memory
    /// store, but (unlike `isUITesting`) keeps all test-only chrome hidden so the app
    /// looks exactly as a user would see it. Used for screenshots / screen recordings.
    static let isShowcase: Bool = environmentFlag("MARBLE_SHOWCASE")
    static let disableAnimations: Bool = environmentFlag("MARBLE_DISABLE_ANIMATIONS") || isUITesting

    /// Whether continuous, decorative motion (particle systems, shimmers)
    /// should freeze to a single representative frame. True when animations are globally disabled
    /// (UI tests) *or* when time is frozen via `overrideNow` (snapshot tests set this in `setUp`),
    /// so `TimelineView`/`Canvas`-driven decoration renders deterministically and never makes a
    /// snapshot flaky. Real users always get full motion (both conditions are false).
    static var reduceDecorativeMotion: Bool {
        disableAnimations || overrideNow != nil
    }
    static let forcedColorScheme: ColorScheme? = TestHooks.parseColorScheme(environmentValue("MARBLE_FORCE_COLOR_SCHEME"))
    static let forcedDynamicType: ContentSizeCategory? = TestHooks.parseContentSize(environmentValue("MARBLE_FORCE_DYNAMIC_TYPE"))
    static let forceReduceTransparency: Bool = environmentFlag("MARBLE_FORCE_REDUCE_TRANSPARENCY")
    static let isAccessibilityAudit: Bool = environmentFlag("MARBLE_A11Y_AUDIT")
    static let fixtureMode: FixtureMode = FixtureMode(rawValue: (environmentValue("MARBLE_FIXTURE_MODE") ?? "populated").lowercased()) ?? .populated
    static let calendarTestDay: String? = environmentValue("MARBLE_TEST_CALENDAR_DAY")?.lowercased()
    static let notificationAuthorizationStatus: String? = environmentValue("MARBLE_NOTIFICATION_AUTHORIZATION")

    static var now: Date {
        if let overrideNow { return overrideNow }
        if let envNow = environmentValue("MARBLE_NOW_ISO8601"), let date = parseISO8601(envNow) {
            return date
        }
        return Date()
    }

    static var resetDatabase: Bool {
        guard isUITesting || isShowcase || environmentFlag("MARBLE_RESET_DB") else { return false }
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static var useInMemoryStore: Bool {
        isUITesting || isShowcase
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

    // A single, branch-free view structure: every override degrades to a no-op when
    // unset, so no AnyView erasure or conditional branches are needed (which would
    // defeat SwiftUI's structural identity and force full re-renders).
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(colorScheme)
            .environment(\.marbleReduceTransparencyOverride, reduceTransparency ? true : nil)
            .transformEnvironment(\.sizeCategory) { category in
                if let sizeCategory {
                    category = sizeCategory
                }
            }
            .transaction { transaction in
                if disableAnimations {
                    transaction.disablesAnimations = true
                }
            }
    }
}
