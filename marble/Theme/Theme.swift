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

    static func applyTabBarAppearance(for scheme: ColorScheme) {
        let resolved = resolvedScheme(scheme)
        let selected = UIColor(primaryTextColor(for: resolved))
        let unselected = UIColor(secondaryTextColor(for: resolved))
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()

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
