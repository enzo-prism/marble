import SwiftUI
import Charts

// The Progress Details visual language. Details is the one Marble surface
// approved for semantic color (see AGENTS.md); these primitives keep that
// color confined to data marks, glyphs and tinted fills while every text run
// stays on the neutral, contrast-pinned theme colors. Surfaces stay solid —
// no glass on content.

// MARK: - Typography

enum TrendsFont {
    /// The one oversized number per screen (the Pulse headline).
    static let hero = Font.system(.largeTitle, design: .rounded).weight(.heavy)
    /// Primary metric values in cards and tiles.
    static let metric = Font.system(.title2, design: .rounded).weight(.bold)
    /// Secondary metric values.
    static let metricSmall = Font.system(.title3, design: .rounded).weight(.semibold)
    /// Section takeaways ("12 of 30 days").
    static let takeaway = Font.system(.subheadline, design: .rounded).weight(.semibold)
    /// Chapter titles ("Training").
    static let chapter = Font.title2.weight(.bold)
    /// Section titles inside a chapter ("Consistency").
    static let section = Font.headline
    /// Uppercase eyebrow labels.
    static let eyebrow = Font.caption.weight(.semibold)
}

// MARK: - Layout

enum TrendsLayout {
    static let cardRadius: CGFloat = 20
    static let innerRadius: CGFloat = 12
    static let cardPadding: CGFloat = MarbleSpacing.m
}

// MARK: - Motion

enum TrendsMotion {
    /// Entrance motion is decorative: off under Reduce Motion, UI tests, and
    /// any XCTest host so snapshots always capture the settled final frame.
    static func isEnabled(reduceMotion: Bool) -> Bool {
        !reduceMotion
            && !TestHooks.disableAnimations
            && !TestHooks.isXCTestProcess
            && !TestHooks.reduceDecorativeMotion
    }

    static let reveal = Animation.spring(response: 0.7, dampingFraction: 0.86)
    static func stagger(_ index: Int) -> Animation {
        reveal.delay(0.04 * Double(min(index, 12)))
    }
}

/// Drives a one-shot entrance (bars growing, rings filling). Starts settled
/// whenever motion is disabled, so the first rendered frame is final.
struct TrendsRevealModifier: ViewModifier {
    @Binding var isRevealed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.onAppear {
            guard !isRevealed else { return }
            if TrendsMotion.isEnabled(reduceMotion: reduceMotion) {
                withAnimation(TrendsMotion.reveal) { isRevealed = true }
            } else {
                isRevealed = true
            }
        }
    }
}

extension View {
    func trendsReveal(_ isRevealed: Binding<Bool>) -> some View {
        modifier(TrendsRevealModifier(isRevealed: isRevealed))
    }
}

/// Initial value for a reveal flag: already revealed when motion is off.
@MainActor
func trendsInitiallyRevealed() -> Bool {
    !TrendsMotion.isEnabled(reduceMotion: UIAccessibility.isReduceMotionEnabled)
}

// MARK: - Color helpers

extension Theme {
    /// Text/glyph color that sits on a full-strength analytics accent. Light
    /// accents are dark and dark-mode accents are light, so the page
    /// background color is always the high-contrast partner.
    static func onAccentColor(for scheme: ColorScheme) -> Color {
        backgroundColor(for: scheme)
    }
}

extension TrendsPalette {
    /// Tinted wash used behind glyphs and pills.
    static func wash(_ accent: Color, scheme: ColorScheme) -> Color {
        accent.opacity(scheme == .dark ? 0.22 : 0.13)
    }

    /// Muscle-group volume band → color. In range reads as "healthy" teal,
    /// room to grow as warm orange, high volume as pink; every bar also
    /// carries its band in text, so hue is never the only cue.
    static func bandColor(_ band: LifterCoaching.VolumeBand, scheme: ColorScheme) -> Color {
        switch band {
        case .below: TrendsPalette.volumeDuration.color(for: scheme)
        case .inRange: TrendsPalette.consistency.color(for: scheme)
        case .high: TrendsPalette.effort.color(for: scheme)
        }
    }

    /// A lit, top-to-bottom fill for medallions and ring segments.
    static func medallionGradient(_ accent: Color) -> LinearGradient {
        LinearGradient(
            colors: [accent.opacity(0.88), accent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Card

struct TrendsCardModifier: ViewModifier {
    var padding: CGFloat = TrendsLayout.cardPadding
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: TrendsLayout.cardRadius, style: .continuous)
                    .fill(Theme.surfaceColor(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: TrendsLayout.cardRadius, style: .continuous)
                    .stroke(Theme.subtleDividerColor(for: colorScheme), lineWidth: 0.75)
            )
    }
}

extension View {
    /// The Details card: solid surface, hairline stroke, generous continuous
    /// corners. Charts render on the card itself (no inner plot fill).
    func trendsCard(padding: CGFloat = TrendsLayout.cardPadding) -> some View {
        modifier(TrendsCardModifier(padding: padding))
    }
}

// MARK: - Section header

/// Title on the left, the one-number takeaway on the right (the HIG's
/// "lead with the insight" chart pattern). Wraps below at large text sizes.
struct TrendsSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var takeaway: String? = nil
    var takeawayGlyph: String? = nil
    var accent: Color? = nil
    var identifier: String? = nil
    var hidesTitleFromAccessibility = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: MarbleSpacing.s) {
                titleBlock
                Spacer(minLength: MarbleSpacing.xs)
                takeawayView.fixedSize()
            }
            VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                titleBlock
                takeawayView
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            titleText
            if let subtitle {
                Text(subtitle)
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var titleText: some View {
        let text = Text(title)
            .font(TrendsFont.section)
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(hidesTitleFromAccessibility)
        if let identifier {
            text.accessibilityIdentifier(identifier)
        } else {
            text
        }
    }

    @ViewBuilder
    private var takeawayView: some View {
        if let takeaway {
            HStack(spacing: MarbleSpacing.xxxs) {
                if let takeawayGlyph {
                    Image(systemName: takeawayGlyph)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent ?? Theme.secondaryTextColor(for: colorScheme))
                        .accessibilityHidden(true)
                }
                Text(takeaway)
                    .font(TrendsFont.takeaway)
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            }
        }
    }
}

// MARK: - Delta pill

/// "▲ 14%" — change versus the previous comparable period. Growth is tinted
/// with the metric's accent; a dip stays neutral (information, never shame).
struct TrendsDeltaPill: View {
    let percent: Double
    let accent: Color
    var comparisonLabel: String = "previous period"

    @Environment(\.colorScheme) private var colorScheme

    private var isFlat: Bool { abs(percent) < 0.5 }
    private var isUp: Bool { percent > 0 }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isFlat ? "equal" : (isUp ? "arrow.up.right" : "arrow.down.right"))
                .font(.caption2.weight(.heavy))
                .foregroundStyle(isUp && !isFlat ? accent : Theme.secondaryTextColor(for: colorScheme))
            Text(text)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
        }
        .padding(.horizontal, MarbleSpacing.xs)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(
                isUp && !isFlat
                    ? TrendsPalette.wash(accent, scheme: colorScheme)
                    : Theme.chipFillColor(for: colorScheme)
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var text: String { Self.text(for: percent) }

    private var accessibilityText: String {
        Self.accessibilityText(for: percent, comparisonLabel: comparisonLabel)
    }

    /// Gains of +200% or more read as a multiple ("3.4×", "11×"): a percentage
    /// that large — or a capped "999+%" — says nothing a person can picture.
    nonisolated static func multiple(for percent: Double) -> Double? {
        percent >= 200 ? 1 + percent / 100 : nil
    }

    nonisolated static func text(for percent: Double) -> String {
        if abs(percent) < 0.5 { return "Even" }
        if let multiple = multiple(for: percent) {
            // Past 10× the comparison week was a token amount; the exact
            // multiple ("2222×") is noise, so it reads as a bound.
            return multiple >= 10 ? "10×+" : "\(multipleText(multiple))×"
        }
        return "\(String(format: "%.0f", abs(percent)))%"
    }

    nonisolated static func accessibilityText(for percent: Double, comparisonLabel: String) -> String {
        if abs(percent) < 0.5 { return "Even with the \(comparisonLabel)" }
        if let multiple = multiple(for: percent) {
            return multiple >= 10
                ? "More than 10 times the \(comparisonLabel)"
                : "\(multipleText(multiple)) times the \(comparisonLabel)"
        }
        return "\(percent > 0 ? "Up" : "Down") \(String(format: "%.0f", abs(percent))) percent from the \(comparisonLabel)"
    }

    nonisolated private static func multipleText(_ multiple: Double) -> String {
        let text = String(format: "%.1f", multiple)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}

// MARK: - Glyph badge

/// A symbol on a tinted rounded square — the chapter and tile icon.
struct TrendsGlyphBadge: View {
    let systemName: String
    let accent: Color
    var size: CGFloat = 28
    var filled = false

    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let side = size * min(max(scale, 1), 1.6)
        Image(systemName: systemName)
            .font(.system(size: side * 0.48, weight: .bold))
            .foregroundStyle(filled ? Theme.onAccentColor(for: colorScheme) : accent)
            .frame(width: side, height: side)
            .background(
                RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
                    .fill(filled
                        ? AnyShapeStyle(TrendsPalette.medallionGradient(accent))
                        : AnyShapeStyle(TrendsPalette.wash(accent, scheme: colorScheme)))
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Shared chart axes

enum TrendsAxes {
    /// Trailing value axis: quiet dashed gridlines, compact labels.
    @AxisContentBuilder
    static func value(scheme: ColorScheme, desiredCount: Int = 3, compact: Bool = false) -> some AxisContent {
        AxisMarks(position: .trailing, values: .automatic(desiredCount: desiredCount)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                .foregroundStyle(Theme.subtleDividerColor(for: scheme))
            AxisValueLabel {
                if let number = value.as(Double.self) {
                    Text(compact
                        ? Formatters.compactNumberText(number)
                        : (Formatters.weight.string(from: NSNumber(value: number)) ?? "\(number)"))
                } else if let number = value.as(Int.self) {
                    Text("\(number)")
                }
            }
            .font(.caption2)
            .foregroundStyle(Theme.secondaryTextColor(for: scheme))
        }
    }

    /// Hairline date axis shared by the time-series charts in Details.
    @AxisContentBuilder
    static func date(scheme: ColorScheme, desiredCount: Int = 3) -> some AxisContent {
        AxisMarks(values: .automatic(desiredCount: desiredCount)) { _ in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                .foregroundStyle(Theme.subtleDividerColor(for: scheme))
            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                .font(.caption2)
                .foregroundStyle(Theme.secondaryTextColor(for: scheme))
        }
    }
}

/// End-of-line marker: accent core ringed with the card surface.
struct TrendsEndpointDot: View {
    let accent: Color
    var size: CGFloat = 9

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Circle()
            .fill(accent)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Theme.surfaceColor(for: colorScheme), lineWidth: 2))
            .background(Circle().fill(accent.opacity(0.22)).frame(width: size * 2.2, height: size * 2.2))
    }
}

// MARK: - Stat row

struct TrendsStat: Identifiable {
    let symbol: String
    let accent: Color
    let value: String
    let unit: String?
    let label: String

    var id: String { label }
}

/// Two or three small facts under a chart ("4 days · Current streak").
/// Side by side when they fit, stacked at large text sizes.
struct TrendsStatRow: View {
    let stats: [TrendsStat]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: MarbleSpacing.s) {
                ForEach(stats) { stat in
                    TrendsStatCell(stat: stat)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                ForEach(stats) { stat in
                    TrendsStatCell(stat: stat)
                }
            }
        }
    }
}

private struct TrendsStatCell: View {
    let stat: TrendsStat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: MarbleSpacing.xs) {
            TrendsGlyphBadge(systemName: stat.symbol, accent: stat.accent, size: 26)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(stat.value)
                        .font(TrendsFont.metricSmall)
                        .monospacedDigit()
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    if let unit = stat.unit {
                        Text(unit)
                            .font(MarbleTypography.rowMeta.weight(.semibold))
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                }
                .fixedSize()
                Text(stat.label)
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stat.label), \([stat.value, stat.unit].compactMap { $0 }.joined(separator: " "))")
    }
}

// MARK: - Single-session note

/// Stands in for a trend chart that has only one point. A lone dot on an empty
/// plot answers nothing; the value plus what unlocks the trend does
/// (HIG Charting data: chart only what a chart can show).
struct TrendsSingleSessionNote: View {
    let date: Date
    let valueText: String
    var message = "Log one more session to see the trend."
    let accent: Color
    let identifier: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: MarbleSpacing.s) {
            TrendsGlyphBadge(systemName: "chart.dots.scatter", accent: accent, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(valueText)
                    .font(TrendsFont.metricSmall)
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                Text(date, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                Text(message)
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(MarbleSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TrendsLayout.innerRadius, style: .continuous)
                .fill(TrendsPalette.wash(accent, scheme: colorScheme))
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
