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

    func testAnalyticsAccentsRemainLegibleInBothAppearancesAndContrastSettings() {
        let accents: [(String, TrendsChartAccent)] = [
            ("Consistency", TrendsPalette.consistency),
            ("Weighted volume", TrendsPalette.volumeWeighted),
            ("Reps", TrendsPalette.volumeReps),
            ("Duration", TrendsPalette.volumeDuration),
            ("Supplements", TrendsPalette.supplements),
            ("Personal records", TrendsPalette.personalRecord),
            ("Strength", TrendsPalette.strength),
            ("Effort", TrendsPalette.effort),
            ("Bodyweight", TrendsPalette.bodyweight)
        ]
        for scheme in [ColorScheme.light, .dark] {
            for (name, accent) in accents {
                var previousRatio: Double = 0
                for contrast in [UIAccessibilityContrast.normal, .high] {
                    let traits = UITraitCollection(mutations: { $0.accessibilityContrast = contrast })
                    let ink = rgb(accent.color(for: scheme), traits: traits)
                    let backgrounds = [Theme.backgroundColor(for: scheme), Theme.surfaceColor(for: scheme)]
                    for background in backgrounds {
                        let paper = rgb(background, traits: traits)
                        let ratio = rgbContrast(ink, paper)
                        XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name), \(scheme), \(contrast): metric text")
                        // The least opaque end of the chart's actual gradient.
                        let bar = zip(ink, paper).map { $0 * 0.84 + $1 * 0.16 }
                        XCTAssertGreaterThanOrEqual(rgbContrast(bar, paper), 3, "\(name): chart marks")
                    }
                    let ratio = rgbContrast(ink, rgb(Theme.backgroundColor(for: scheme), traits: traits))
                    if contrast == .high {
                        XCTAssertGreaterThan(ratio, previousRatio, "Increase Contrast must strengthen \(name)")
                    }
                    previousRatio = ratio
                }
            }
        }
    }

    private func rgb(_ color: Color, traits: UITraitCollection) -> [Double] {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(UIColor(color).resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return [Double(red), Double(green), Double(blue)]
    }

    private func rgbContrast(_ first: [Double], _ second: [Double]) -> Double {
        func luminance(_ components: [Double]) -> Double {
            zip(components, [0.2126, 0.7152, 0.0722]).reduce(0) {
                $0 + relativeLuminance($1.0) * $1.1
            }
        }
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
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
