import SwiftUI
import UIKit

enum ThemePalette {
    static let lightBackground: Double = 1.0
    static let darkBackground: Double = 0.0
    static let lightPrimaryText: Double = 0.0
    static let darkPrimaryText: Double = 1.0
    static let lightSecondaryText: Double = 0.2
    static let darkSecondaryText: Double = 0.8
    static let lightDivider: Double = 0.3
    static let darkDivider: Double = 0.5
    static let lightChipFill: Double = 0.92
    static let darkChipFill: Double = 0.18
    static let lightSurfaceFill: Double = 0.985
    static let darkSurfaceFill: Double = 0.035
    static let lightControlFill: Double = 0.95
    static let darkControlFill: Double = 0.12
    static let lightSubtleDivider: Double = 0.82
    static let darkSubtleDivider: Double = 0.28
    static let lightDestructiveAction: Double = 0.2
    static let darkDestructiveAction: Double = 0.25
}

enum Theme {
    private static func resolvedScheme(_ scheme: ColorScheme) -> ColorScheme {
        TestHooks.forcedColorScheme ?? scheme
    }

    static func backgroundColor(for scheme: ColorScheme) -> Color {
        let resolved = resolvedScheme(scheme)
        return resolved == .dark ? Color(white: ThemePalette.darkBackground) : Color(white: ThemePalette.lightBackground)
    }

    static func primaryTextColor(for scheme: ColorScheme) -> Color {
        let resolved = resolvedScheme(scheme)
        return resolved == .dark ? Color(white: ThemePalette.darkPrimaryText) : Color(white: ThemePalette.lightPrimaryText)
    }

    static func secondaryTextColor(for scheme: ColorScheme) -> Color {
        let resolved = resolvedScheme(scheme)
        return resolved == .dark ? Color(white: ThemePalette.darkSecondaryText) : Color(white: ThemePalette.lightSecondaryText)
    }

    static func dividerColor(for scheme: ColorScheme) -> Color {
        let resolved = resolvedScheme(scheme)
        return resolved == .dark ? Color(white: ThemePalette.darkDivider) : Color(white: ThemePalette.lightDivider)
    }

    static func chipFillColor(for scheme: ColorScheme) -> Color {
        let resolved = resolvedScheme(scheme)
        return resolved == .dark ? Color(white: ThemePalette.darkChipFill) : Color(white: ThemePalette.lightChipFill)
    }

    static func surfaceColor(for scheme: ColorScheme) -> Color {
        let resolved = resolvedScheme(scheme)
        return resolved == .dark ? Color(white: ThemePalette.darkSurfaceFill) : Color(white: ThemePalette.lightSurfaceFill)
    }

    static func controlFillColor(for scheme: ColorScheme) -> Color {
        let resolved = resolvedScheme(scheme)
        return resolved == .dark ? Color(white: ThemePalette.darkControlFill) : Color(white: ThemePalette.lightControlFill)
    }

    static func subtleDividerColor(for scheme: ColorScheme) -> Color {
        let resolved = resolvedScheme(scheme)
        return resolved == .dark ? Color(white: ThemePalette.darkSubtleDivider) : Color(white: ThemePalette.lightSubtleDivider)
    }

    static func destructiveActionColor(for scheme: ColorScheme) -> Color {
        let resolved = resolvedScheme(scheme)
        return resolved == .dark
            ? Color(white: ThemePalette.darkDestructiveAction)
            : Color(white: ThemePalette.lightDestructiveAction)
    }

    /// On-state tint for switches. Marble's content stays monochrome, but a
    /// switch is a system control where the platform-standard green is the
    /// clearest, most familiar "on" signal. `Color.green` resolves to
    /// systemGreen, which adapts and keeps sufficient contrast in light/dark.
    static let toggleOnColor: Color = .green

    static func applyTabBarAppearance(for scheme: ColorScheme) {
        let resolved = resolvedScheme(scheme)
        let selected = UIColor(primaryTextColor(for: resolved))
        let unselected = UIColor(secondaryTextColor(for: resolved))
        let appearance = UITabBarAppearance()

        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(backgroundColor(for: resolved))
        appearance.shadowColor = UIColor(subtleDividerColor(for: resolved))

        let stacked = appearance.stackedLayoutAppearance
        stacked.normal.iconColor = unselected
        stacked.normal.titleTextAttributes = [.foregroundColor: unselected]
        stacked.selected.iconColor = selected
        stacked.selected.titleTextAttributes = [.foregroundColor: selected]

        let inline = appearance.inlineLayoutAppearance
        inline.normal.iconColor = unselected
        inline.normal.titleTextAttributes = [.foregroundColor: unselected]
        inline.selected.iconColor = selected
        inline.selected.titleTextAttributes = [.foregroundColor: selected]

        let compact = appearance.compactInlineLayoutAppearance
        compact.normal.iconColor = unselected
        compact.normal.titleTextAttributes = [.foregroundColor: unselected]
        compact.selected.iconColor = selected
        compact.selected.titleTextAttributes = [.foregroundColor: selected]

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.unselectedItemTintColor = unselected
        tabBar.tintColor = selected
    }
}
