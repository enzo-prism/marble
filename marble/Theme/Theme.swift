import SwiftUI
import UIKit

enum ThemePalette {
    static let lightBackground: Double = 1.0
    static let darkBackground: Double = 0.0
    static let lightPrimaryText: Double = 0.0
    static let darkPrimaryText: Double = 1.0
    static let lightSecondaryText: Double = 0.2
    static let darkSecondaryText: Double = 0.8
    static let lightSecondaryTextHighContrast: Double = 0.08
    static let darkSecondaryTextHighContrast: Double = 0.92
    static let lightDivider: Double = 0.3
    static let darkDivider: Double = 0.5
    static let lightDividerHighContrast: Double = 0.18
    static let darkDividerHighContrast: Double = 0.72
    static let lightChipFill: Double = 0.92
    static let darkChipFill: Double = 0.18
    static let lightChipFillHighContrast: Double = 0.86
    static let darkChipFillHighContrast: Double = 0.24
    static let lightSurfaceFill: Double = 0.985
    static let darkSurfaceFill: Double = 0.035
    static let lightSurfaceFillHighContrast: Double = 0.96
    static let darkSurfaceFillHighContrast: Double = 0.06
    static let lightControlFill: Double = 0.95
    static let darkControlFill: Double = 0.12
    static let lightControlFillHighContrast: Double = 0.88
    static let darkControlFillHighContrast: Double = 0.22
    static let lightSubtleDivider: Double = 0.82
    static let darkSubtleDivider: Double = 0.28
    static let lightSubtleDividerHighContrast: Double = 0.58
    static let darkSubtleDividerHighContrast: Double = 0.46
    static let lightDestructiveAction: Double = 0.2
    static let darkDestructiveAction: Double = 0.8
    static let lightDestructiveActionHighContrast: Double = 0.08
    static let darkDestructiveActionHighContrast: Double = 0.92
}

enum Theme {
    nonisolated private static func resolvedScheme(_ scheme: ColorScheme) -> ColorScheme {
        TestHooks.forcedColorScheme ?? scheme
    }

    /// Keeps Marble's monochrome identity while honoring Increase Contrast.
    /// SwiftUI reevaluates the dynamic UIColor provider whenever the system's
    /// accessibility contrast changes, including while the app is running.
    nonisolated private static func adaptiveGray(
        for scheme: ColorScheme,
        standardLight: Double,
        standardDark: Double,
        highContrastLight: Double,
        highContrastDark: Double
    ) -> Color {
        let resolved = resolvedScheme(scheme)
        return Color(uiColor: UIColor { traits in
            let usesDarkValue = resolved == .dark
            let value: Double
            if traits.accessibilityContrast == .high {
                value = usesDarkValue ? highContrastDark : highContrastLight
            } else {
                value = usesDarkValue ? standardDark : standardLight
            }
            return UIColor(white: value, alpha: 1)
        })
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
        adaptiveGray(
            for: scheme,
            standardLight: ThemePalette.lightSecondaryText,
            standardDark: ThemePalette.darkSecondaryText,
            highContrastLight: ThemePalette.lightSecondaryTextHighContrast,
            highContrastDark: ThemePalette.darkSecondaryTextHighContrast
        )
    }

    static func dividerColor(for scheme: ColorScheme) -> Color {
        adaptiveGray(
            for: scheme,
            standardLight: ThemePalette.lightDivider,
            standardDark: ThemePalette.darkDivider,
            highContrastLight: ThemePalette.lightDividerHighContrast,
            highContrastDark: ThemePalette.darkDividerHighContrast
        )
    }

    static func chipFillColor(for scheme: ColorScheme) -> Color {
        adaptiveGray(
            for: scheme,
            standardLight: ThemePalette.lightChipFill,
            standardDark: ThemePalette.darkChipFill,
            highContrastLight: ThemePalette.lightChipFillHighContrast,
            highContrastDark: ThemePalette.darkChipFillHighContrast
        )
    }

    static func surfaceColor(for scheme: ColorScheme) -> Color {
        adaptiveGray(
            for: scheme,
            standardLight: ThemePalette.lightSurfaceFill,
            standardDark: ThemePalette.darkSurfaceFill,
            highContrastLight: ThemePalette.lightSurfaceFillHighContrast,
            highContrastDark: ThemePalette.darkSurfaceFillHighContrast
        )
    }

    static func controlFillColor(for scheme: ColorScheme) -> Color {
        adaptiveGray(
            for: scheme,
            standardLight: ThemePalette.lightControlFill,
            standardDark: ThemePalette.darkControlFill,
            highContrastLight: ThemePalette.lightControlFillHighContrast,
            highContrastDark: ThemePalette.darkControlFillHighContrast
        )
    }

    static func subtleDividerColor(for scheme: ColorScheme) -> Color {
        adaptiveGray(
            for: scheme,
            standardLight: ThemePalette.lightSubtleDivider,
            standardDark: ThemePalette.darkSubtleDivider,
            highContrastLight: ThemePalette.lightSubtleDividerHighContrast,
            highContrastDark: ThemePalette.darkSubtleDividerHighContrast
        )
    }

    static func destructiveActionColor(for scheme: ColorScheme) -> Color {
        adaptiveGray(
            for: scheme,
            standardLight: ThemePalette.lightDestructiveAction,
            standardDark: ThemePalette.darkDestructiveAction,
            highContrastLight: ThemePalette.lightDestructiveActionHighContrast,
            highContrastDark: ThemePalette.darkDestructiveActionHighContrast
        )
    }

    /// Semantic sprint-result colors. Marble stays monochrome everywhere else;
    /// these two accents are reserved for an athlete's recorded goal result.
    /// The light variants are deliberately darker than the default system
    /// colors so compact bold labels retain contrast on white.
    static func sprintGoalHitColor(for scheme: ColorScheme) -> Color {
        let resolved = resolvedScheme(scheme)
        return resolved == .dark
            ? Color(red: 0.30, green: 0.92, blue: 0.48)
            : Color(red: 0.00, green: 0.36, blue: 0.13)
    }

    static func sprintGoalMissColor(for scheme: ColorScheme) -> Color {
        let resolved = resolvedScheme(scheme)
        return resolved == .dark
            ? Color(red: 1.00, green: 0.42, blue: 0.38)
            : Color(red: 0.70, green: 0.02, blue: 0.06)
    }

    static func applyTabBarAppearance(for scheme: ColorScheme) {
        let resolved = resolvedScheme(scheme)
        let selected = UIColor(primaryTextColor(for: resolved))
        let unselected = UIColor(secondaryTextColor(for: resolved))
        let tabBar = UITabBar.appearance()

        // SwiftUI owns the Reduce Transparency background so changes are
        // reflected live. Keep this global proxy limited to item colors;
        // persisting an opaque appearance can leave the bar stale afterward.
        tabBar.unselectedItemTintColor = unselected
        tabBar.tintColor = selected
    }
}
