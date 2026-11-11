import SwiftUI
import UIKit

/// Semantic analytics colors, explicitly approved for Progress Details. Text,
/// axes and navigation retain the neutral theme; labels and shapes carry the
/// same information as color. Separate appearances keep data marks legible.
struct TrendsChartAccent {
    let light: Color
    let dark: Color

    func color(for scheme: ColorScheme) -> Color {
        let usesDark = (TestHooks.forcedColorScheme ?? scheme) == .dark
        let base = UIColor(usesDark ? dark : light)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard base.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return Color(uiColor: base)
        }
        // Increase Contrast strengthens the same hue toward the foreground,
        // preserving each metric's identity when the setting changes at runtime.
        let channels = (red, green, blue)
        return Color(uiColor: UIColor { traits in
            guard traits.accessibilityContrast == .high else { return base }
            let foreground: CGFloat = usesDark ? 1 : 0
            return UIColor(
                red: channels.0 * 0.82 + foreground * 0.18,
                green: channels.1 * 0.82 + foreground * 0.18,
                blue: channels.2 * 0.82 + foreground * 0.18,
                alpha: 1
            )
        })
    }
}

enum TrendsPalette {
    static let consistency = TrendsChartAccent(
        light: Color(red: 0.00, green: 0.42, blue: 0.40),
        dark: Color(red: 0.30, green: 0.80, blue: 0.74)
    )
    static let volumeWeighted = TrendsChartAccent(
        light: Color(red: 0.05, green: 0.36, blue: 0.76),
        dark: Color(red: 0.38, green: 0.67, blue: 1.00)
    )
    static let volumeReps = TrendsChartAccent(
        light: Color(red: 0.48, green: 0.24, blue: 0.72),
        dark: Color(red: 0.76, green: 0.58, blue: 1.00)
    )
    static let volumeDuration = TrendsChartAccent(
        light: Color(red: 0.68, green: 0.32, blue: 0.04),
        dark: Color(red: 1.00, green: 0.65, blue: 0.31)
    )
    static let supplements = TrendsChartAccent(
        light: Color(red: 0.18, green: 0.43, blue: 0.21),
        dark: Color(red: 0.49, green: 0.80, blue: 0.48)
    )
    static let progress = volumeWeighted
    static let personalRecord = TrendsChartAccent(
        light: Color(red: 0.56, green: 0.39, blue: 0.02),
        dark: Color(red: 1.00, green: 0.80, blue: 0.36)
    )
    static let strength = TrendsChartAccent(
        light: Color(red: 0.31, green: 0.29, blue: 0.72),
        dark: Color(red: 0.65, green: 0.64, blue: 1.00)
    )
    static let effort = TrendsChartAccent(
        light: Color(red: 0.68, green: 0.20, blue: 0.44),
        dark: Color(red: 1.00, green: 0.52, blue: 0.73)
    )
    static let bodyweight = TrendsChartAccent(
        light: Color(red: 0.00, green: 0.40, blue: 0.57),
        dark: Color(red: 0.34, green: 0.76, blue: 0.94)
    )
    static let sprint = volumeDuration

    /// Categorical comparisons retain direct axis labels and numeric values.
    /// Mapping is identity-based so a filter/reorder never changes a category's color.
    static func muscleGroup(_ category: ExerciseCategory) -> TrendsChartAccent {
        switch category {
        case .chest: volumeReps
        case .back: consistency
        case .shoulders: strength
        case .biceps: volumeWeighted
        case .triceps: effort
        case .core: personalRecord
        case .quads, .legs: volumeWeighted
        case .hamstrings: bodyweight
        case .calves: supplements
        case .run, .power: volumeDuration
        case .bar: strength
        case .recover: consistency
        case .other: progress
        }
    }

    static func repRange(_ kind: LifterAnalytics.RepRangeBucketKind) -> TrendsChartAccent {
        switch kind {
        case .strength: strength
        case .hypertrophy: volumeReps
        case .endurance: volumeDuration
        }
    }

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

/// Labeled color-and-shape key used under multi-series charts in place of
/// the default Swift Charts legend.
struct TrendsLegendChip: View {
    let label: String
    let color: Color
    let symbol: TrendsLegendSymbol

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: MarbleSpacing.xxs) {
            TrendsLegendGlyph(color: color, symbol: symbol)
            Text(label)
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

}

/// The same glyph is used in the legend and above its bars, so a hue is never
/// the only way to identify a volume series.
struct TrendsLegendGlyph: View {
    let color: Color
    let symbol: TrendsLegendSymbol
    @ViewBuilder var body: some View {
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
