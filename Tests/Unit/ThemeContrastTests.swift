import XCTest
import SwiftUI
import UIKit
@testable import marble

@MainActor
final class ThemeContrastTests: MarbleTestCase {
    func testPrimaryTextContrast() {
        let lightRatio = contrastRatio(ThemePalette.lightPrimaryText, ThemePalette.lightBackground)
        XCTAssertGreaterThanOrEqual(lightRatio, 4.5, "Light primary text should be >= 4.5:1")

        let darkRatio = contrastRatio(ThemePalette.darkPrimaryText, ThemePalette.darkBackground)
        XCTAssertGreaterThanOrEqual(darkRatio, 4.5, "Dark primary text should be >= 4.5:1")
    }

    func testSecondaryTextContrast() {
        let lightRatio = contrastRatio(ThemePalette.lightSecondaryText, ThemePalette.lightBackground)
        XCTAssertGreaterThanOrEqual(lightRatio, 4.5, "Light secondary text should be >= 4.5:1")

        let darkRatio = contrastRatio(ThemePalette.darkSecondaryText, ThemePalette.darkBackground)
        XCTAssertGreaterThanOrEqual(darkRatio, 4.5, "Dark secondary text should be >= 4.5:1")

        let lightHighContrastRatio = contrastRatio(ThemePalette.lightSecondaryTextHighContrast, ThemePalette.lightBackground)
        XCTAssertGreaterThan(lightHighContrastRatio, lightRatio, "Increase Contrast should strengthen light secondary text")

        let darkHighContrastRatio = contrastRatio(ThemePalette.darkSecondaryTextHighContrast, ThemePalette.darkBackground)
        XCTAssertGreaterThan(darkHighContrastRatio, darkRatio, "Increase Contrast should strengthen dark secondary text")
    }

    func testDividerContrast() {
        let lightRatio = contrastRatio(ThemePalette.lightDivider, ThemePalette.lightBackground)
        XCTAssertGreaterThanOrEqual(lightRatio, 3.0, "Light divider should be >= 3:1")

        let darkRatio = contrastRatio(ThemePalette.darkDivider, ThemePalette.darkBackground)
        XCTAssertGreaterThanOrEqual(darkRatio, 3.0, "Dark divider should be >= 3:1")

        let lightHighContrastRatio = contrastRatio(ThemePalette.lightDividerHighContrast, ThemePalette.lightBackground)
        XCTAssertGreaterThan(lightHighContrastRatio, lightRatio, "Increase Contrast should strengthen light dividers")

        let darkHighContrastRatio = contrastRatio(ThemePalette.darkDividerHighContrast, ThemePalette.darkBackground)
        XCTAssertGreaterThan(darkHighContrastRatio, darkRatio, "Increase Contrast should strengthen dark dividers")
    }

    func testDestructiveActionContrast() {
        let lightRatio = contrastRatio(ThemePalette.lightDestructiveAction, ThemePalette.lightBackground)
        XCTAssertGreaterThanOrEqual(lightRatio, 4.5, "Light destructive actions should be >= 4.5:1")

        let darkRatio = contrastRatio(ThemePalette.darkDestructiveAction, ThemePalette.darkBackground)
        XCTAssertGreaterThanOrEqual(darkRatio, 4.5, "Dark destructive actions should be >= 4.5:1")
    }

    func testAdaptiveSecondaryTextResolvesForIncreaseContrast() {
        let highContrastTraits = UITraitCollection(mutations: { traits in
            traits.accessibilityContrast = .high
        })

        assertGray(
            UIColor(Theme.secondaryTextColor(for: .light)).resolvedColor(with: highContrastTraits),
            equals: ThemePalette.lightSecondaryTextHighContrast
        )
        assertGray(
            UIColor(Theme.secondaryTextColor(for: .dark)).resolvedColor(with: highContrastTraits),
            equals: ThemePalette.darkSecondaryTextHighContrast
        )
    }

    private func assertGray(_ color: UIColor, equals expected: Double) {
        var white: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(color.getWhite(&white, alpha: &alpha))
        XCTAssertEqual(white, expected, accuracy: 0.001)
        XCTAssertEqual(alpha, 1, accuracy: 0.001)
    }

    private func contrastRatio(_ c1: Double, _ c2: Double) -> Double {
        let l1 = relativeLuminance(c1)
        let l2 = relativeLuminance(c2)
        let (lighter, darker) = l1 >= l2 ? (l1, l2) : (l2, l1)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ component: Double) -> Double {
        if component <= 0.03928 {
            return component / 12.92
        }
        return pow((component + 0.055) / 1.055, 2.4)
    }
}
