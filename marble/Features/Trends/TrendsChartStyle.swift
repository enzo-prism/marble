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

/// Progress Details color system (v3, 2026-11-25).
///
/// Six roles, each with exactly one meaning everywhere it appears (HIG Color:
/// "Avoid using the same color to mean different things"). Values are tuned in
/// OKLCH so the family shares one lightness and chroma: light-mode marks sit at
/// 3:1 or better against white without going muddy, and dark-mode marks are
/// brighter, slightly desaturated partners rather than inversions. Neutral
/// grey carries "not yet" states so color always signals something. Bars are
/// solid — no translucent sheen — so every mark keeps the full 3:1 non-text
/// contrast (WCAG 1.4.11) its hue was tuned for.
enum TrendsPalette {
    /// Training load and frequency: sessions, sets, consistency, weighted
    /// volume, the weekly goal, a muscle that is in range, the hypertrophy band.
    static let training = TrendsChartAccent(
        light: Color(red: 0.000, green: 0.444, blue: 0.877),
        dark: Color(red: 0.388, green: 0.703, blue: 1.000)
    )
    /// Strength: estimated 1RMs, lifts, bodyweight reps, the strength band.
    static let strength = TrendsChartAccent(
        light: Color(red: 0.454, green: 0.275, blue: 0.846),
        dark: Color(red: 0.697, green: 0.611, blue: 0.996)
    )
    /// Effort: RPE and high training volume.
    static let effort = TrendsChartAccent(
        light: Color(red: 0.840, green: 0.227, blue: 0.501),
        dark: Color(red: 0.986, green: 0.523, blue: 0.693)
    )
    /// Records: PRs, best weeks, trophies, a goal beaten.
    static let record = TrendsChartAccent(
        light: Color(red: 0.819, green: 0.432, blue: 0.024),
        dark: Color(red: 1.000, green: 0.741, blue: 0.278)
    )
    /// Endurance: duration, distance, pace, sprints, the endurance band.
    static let endurance = TrendsChartAccent(
        light: Color(red: 0.000, green: 0.538, blue: 0.584),
        dark: Color(red: 0.302, green: 0.831, blue: 0.858)
    )
    /// Body & Habits: bodyweight and supplements.
    static let body = TrendsChartAccent(
        light: Color(red: 0.118, green: 0.578, blue: 0.283),
        dark: Color(red: 0.411, green: 0.851, blue: 0.551)
    )
    /// Neutral data ink for "not there yet" states (a muscle below range).
    static let quiet = TrendsChartAccent(
        light: Color(white: 0.52),
        dark: Color(white: 0.56)
    )

    // Section-facing names. Each resolves to one of the roles above, so two
    // charts showing the same kind of data always share a hue.
    static let consistency = training
    static let volumeWeighted = training
    static let progress = training
    static let volumeReps = strength
    static let volumeDuration = endurance
    static let sprint = endurance
    static let personalRecord = record
    static let bodyweight = body
    static let supplements = body

    static func repRange(_ kind: LifterAnalytics.RepRangeBucketKind) -> TrendsChartAccent {
        switch kind {
        case .strength: strength
        case .hypertrophy: training
        case .endurance: endurance
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

}

extension TrendsPalette {
    /// `accent` laid over the card surface at `opacity`, flattened to one
    /// opaque color so whatever sits on it can be contrast-checked.
    static func ramp(_ accent: Color, opacity: Double, scheme: ColorScheme) -> Color {
        let top = rgba(accent)
        let base = rgba(Theme.surfaceColor(for: scheme))
        let alpha = min(max(opacity, 0), 1)
        return Color(
            red: top.0 * alpha + base.0 * (1 - alpha),
            green: top.1 * alpha + base.1 * (1 - alpha),
            blue: top.2 * alpha + base.2 * (1 - alpha)
        )
    }

    /// Heatmap intensity ramp, level 1 (lightest) to 4 (full hue).
    nonisolated static func heatmapOpacity(for level: Int) -> Double {
        switch level {
        case 1: 0.3
        case 2: 0.52
        case 3: 0.76
        default: 1
        }
    }

    /// Primary text or the on-accent color, whichever has more contrast on
    /// `fill` (WCAG relative luminance). Keeps day numbers legible at every
    /// heatmap level in both appearances.
    static func legibleText(on fill: Color, scheme: ColorScheme) -> Color {
        let primary = Theme.primaryTextColor(for: scheme)
        let onAccent = Theme.onAccentColor(for: scheme)
        let background = luminance(fill)
        return contrast(luminance(primary), background) >= contrast(luminance(onAccent), background)
            ? primary
            : onAccent
    }

    static func luminance(_ color: Color) -> Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let channels = rgba(color)
        return 0.2126 * linear(channels.0) + 0.7152 * linear(channels.1) + 0.0722 * linear(channels.2)
    }

    static func contrast(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private static func rgba(_ color: Color) -> (Double, Double, Double) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(color).resolvedColor(with: UITraitCollection.current)
            .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (Double(red), Double(green), Double(blue))
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

/// Direct labels live above each bar rather than outside the plot. Long values
/// and accessibility text can wrap without colliding with neighboring marks.
/// The section supplies the same Audio Graph descriptor as its other charts.
struct TrendsCategoryBar: View {
    let title: String
    let valueText: String
    let accessibilityValue: String
    let value: Double
    let maximum: Double
    let accent: Color
    var guideBand: ClosedRange<Double>? = nil
    /// Tint for the shaded guide zone; defaults to the consistency accent.
    var guideBandColor: Color? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRevealed = trendsInitiallyRevealed()

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: MarbleSpacing.s) {
                    categoryLabel.fixedSize()
                    Spacer(minLength: MarbleSpacing.s)
                    metricLabel.fixedSize()
                }
                VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                    categoryLabel
                    metricLabel
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            GeometryReader { proxy in
                let domainMaximum = max(maximum, 1)
                let fraction = min(max(value / domainMaximum, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.chipFillColor(for: colorScheme))
                    if let guideBand {
                        let lower = proxy.size.width * min(max(guideBand.lowerBound / domainMaximum, 0), 1)
                        let upper = proxy.size.width * min(max(guideBand.upperBound / domainMaximum, 0), 1)
                        let zone = guideBandColor ?? TrendsPalette.consistency.color(for: colorScheme)
                        Rectangle()
                            .fill(zone.opacity(colorScheme == .dark ? 0.22 : 0.16))
                            .frame(width: max(upper - lower, 0))
                            .offset(x: lower)
                        Path { path in
                            for x in [lower, upper] {
                                path.move(to: CGPoint(x: x, y: -2))
                                path.addLine(to: CGPoint(x: x, y: proxy.size.height + 2))
                            }
                        }
                        .stroke(zone.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    }
                    Capsule()
                        .fill(accent)
                        .frame(width: max(proxy.size.width * fraction * (isRevealed ? 1 : 0), value > 0 ? 6 : 0))
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .trendsReveal($isRevealed)
        .animation(TrendsMotion.isEnabled(reduceMotion: reduceMotion) ? TrendsMotion.reveal : nil, value: isRevealed)
    }

    private var categoryLabel: some View {
        Text(title)
            .font(MarbleTypography.rowMeta.weight(.semibold))
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
    }

    private var metricLabel: some View {
        Text(valueText)
            .font(MarbleTypography.smallLabel)
            .monospacedDigit()
            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
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
