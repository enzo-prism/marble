import SwiftUI

/// Color identity for one Trends metric. Trends is the single surface where
/// Marble's monochrome brand allows color: one restrained accent per chart,
/// tuned brighter on dark backgrounds so marks stay vivid on pure black and
/// deep enough on white to hold ~3:1 graphical contrast.
struct TrendsChartAccent {
    let light: Color
    let dark: Color

    func color(for scheme: ColorScheme) -> Color {
        (TestHooks.forcedColorScheme ?? scheme) == .dark ? dark : light
    }
}

enum TrendsPalette {
    /// Consistency line + area: indigo.
    static let consistency = TrendsChartAccent(
        light: Color(red: 0.30, green: 0.36, blue: 0.95),
        dark: Color(red: 0.52, green: 0.58, blue: 1.00)
    )

    /// Weekly volume series: a warm family that groups visually but stays
    /// distinguishable bar-to-bar.
    static let volumeWeighted = TrendsChartAccent(
        light: Color(red: 0.93, green: 0.42, blue: 0.10),
        dark: Color(red: 1.00, green: 0.58, blue: 0.26)
    )
    static let volumeReps = TrendsChartAccent(
        light: Color(red: 0.85, green: 0.62, blue: 0.06),
        dark: Color(red: 1.00, green: 0.78, blue: 0.30)
    )
    static let volumeDuration = TrendsChartAccent(
        light: Color(red: 0.76, green: 0.34, blue: 0.28),
        dark: Color(red: 0.94, green: 0.54, blue: 0.46)
    )

    /// Supplements line + area: teal.
    static let supplements = TrendsChartAccent(
        light: Color(red: 0.00, green: 0.55, blue: 0.50),
        dark: Color(red: 0.25, green: 0.80, blue: 0.72)
    )

    /// Per-exercise progress: violet.
    static let progress = TrendsChartAccent(
        light: Color(red: 0.52, green: 0.31, blue: 0.93),
        dark: Color(red: 0.71, green: 0.55, blue: 1.00)
    )

    /// Personal-record markers and trophies: gold.
    static let personalRecord = TrendsChartAccent(
        light: Color(red: 0.80, green: 0.56, blue: 0.04),
        dark: Color(red: 0.97, green: 0.76, blue: 0.26)
    )

    /// Estimated 1RM: steel blue, apart from the violet raw-progress line —
    /// the HIG asks that different data read as visibly different charts.
    static let strength = TrendsChartAccent(
        light: Color(red: 0.16, green: 0.48, blue: 0.85),
        dark: Color(red: 0.45, green: 0.70, blue: 1.00)
    )

    /// Effort (average RPE): the warm red already used for duration volume.
    static let effort = volumeDuration

    /// Bodyweight: a cool slate-green, distinct from the violet raw-progress
    /// line, the steel-blue e1RM line, and the teal supplements line.
    static let bodyweight = TrendsChartAccent(
        light: Color(red: 0.13, green: 0.52, blue: 0.44),
        dark: Color(red: 0.40, green: 0.82, blue: 0.70)
    )

    /// Soft fill under line charts, fading to transparent at the baseline.
    static func areaGradient(_ accent: Color) -> LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [accent.opacity(0.30), accent.opacity(0.02)]),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Vertical sheen for bars so columns read as lit objects, not flat ink.
    static func barGradient(_ accent: Color) -> LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [accent, accent.opacity(0.62)]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Small colored-dot legend entry used under multi-series charts in place of
/// the default Swift Charts legend.
struct TrendsLegendChip: View {
    let label: String
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: MarbleSpacing.xxs) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

/// Selection marker: a soft halo around a solid accent core, ringed with the
/// page background so it pops off the line.
struct TrendsSelectionDot: View {
    let accent: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.20))
                .frame(width: 24, height: 24)
            Circle()
                .fill(accent)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Theme.backgroundColor(for: colorScheme), lineWidth: 2)
                )
        }
    }
}

/// Personal-record marker: a gold ring with a background-knockout center.
struct TrendsPRDot: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Circle()
            .fill(Theme.backgroundColor(for: colorScheme))
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .stroke(TrendsPalette.personalRecord.color(for: colorScheme), lineWidth: 2)
            )
    }
}
