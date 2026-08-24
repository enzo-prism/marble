import SwiftUI

/// Monochrome identity for one Trends metric. Light and dark values remain
/// distinct enough for graphical contrast while preserving Marble's strict
/// black, white, and grey palette.
struct TrendsChartAccent {
    let light: Color
    let dark: Color

    func color(for scheme: ColorScheme) -> Color {
        (TestHooks.forcedColorScheme ?? scheme) == .dark ? dark : light
    }
}

enum TrendsPalette {
    /// Single-series charts use the strongest neutral.
    static let consistency = TrendsChartAccent(
        light: Color(white: 0.10),
        dark: Color(white: 0.90)
    )

    /// Multi-series charts use separated neutral values so adjacent bars stay
    /// distinguishable without introducing brand-breaking color.
    static let volumeWeighted = TrendsChartAccent(
        light: Color(white: 0.08),
        dark: Color(white: 0.92)
    )
    static let volumeReps = TrendsChartAccent(
        light: Color(white: 0.28),
        dark: Color(white: 0.72)
    )
    static let volumeDuration = TrendsChartAccent(
        light: Color(white: 0.48),
        dark: Color(white: 0.52)
    )

    static let supplements = TrendsChartAccent(
        light: Color(white: 0.18),
        dark: Color(white: 0.82)
    )

    static let progress = TrendsChartAccent(
        light: Color(white: 0.12),
        dark: Color(white: 0.88)
    )

    static let personalRecord = TrendsChartAccent(
        light: Color(white: 0.02),
        dark: Color(white: 0.98)
    )

    static let strength = TrendsChartAccent(
        light: Color(white: 0.22),
        dark: Color(white: 0.78)
    )

    static let effort = volumeDuration

    static let bodyweight = TrendsChartAccent(
        light: Color(white: 0.32),
        dark: Color(white: 0.68)
    )

    static let sprint = TrendsChartAccent(
        light: Color(white: 0.40),
        dark: Color(white: 0.60)
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
            gradient: Gradient(colors: [accent, accent.opacity(0.84)]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Small neutral-dot legend entry used under multi-series charts in place of
/// the default Swift Charts legend.
struct TrendsLegendChip: View {
    let label: String
    let color: Color
    let symbol: TrendsLegendSymbol

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: MarbleSpacing.xxs) {
            legendSymbol
            Text(label)
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var legendSymbol: some View {
        switch symbol {
        case .circle:
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        case .square:
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(color)
                .frame(width: 8, height: 8)
        case .triangle:
            Image(systemName: "triangle.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
        }
    }
}

enum TrendsLegendSymbol {
    case circle
    case square
    case triangle
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

/// Personal-record marker: a high-contrast ring with a background-knockout center.
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
