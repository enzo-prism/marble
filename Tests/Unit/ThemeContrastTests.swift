import XCTest
@testable import marble

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
    }

    func testDividerContrast() {
        let lightRatio = contrastRatio(ThemePalette.lightDivider, ThemePalette.lightBackground)
        XCTAssertGreaterThanOrEqual(lightRatio, 3.0, "Light divider should be >= 3:1")

        let darkRatio = contrastRatio(ThemePalette.darkDivider, ThemePalette.darkBackground)
        XCTAssertGreaterThanOrEqual(darkRatio, 3.0, "Dark divider should be >= 3:1")
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
