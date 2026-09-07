import SwiftUI
import UIKit

/// Auto-rotating training quote, shared by the Daily Highlights card and the
/// Progress overview footer. Quotes come from `DailyHighlightQuoteLibrary`'s
/// per-launch session order (the full pool, shuffled once per launch and
/// stable under tests); the schedule and tap-to-hold semantics live in
/// `DailyHighlightQuoteRotation`. Tap advances to the next quote and a
/// horizontal drag swipes back or forward. Pass `centered` for the quiet
/// overview footer treatment (centered text, no counter); the default leading
/// layout with counter is the Daily Highlights card style.
struct DailyHighlightQuoteRotator: View {
    let day: Date
    var centered: Bool = false
    var quotePool: [DailyHighlightQuote]? = nil
    var singleLineFont: UIFont? = nil
    var accessibilityIdentifier: String = "Trends.DailyHighlights.Quote"
    var accessibilityLabel: String = "Daily motivation"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var manualSelection: DailyHighlightQuoteRotation.ManualSelection?

    private let rotationInterval: TimeInterval = 12

    var body: some View {
        let quotes = quotePool ?? DailyHighlightQuoteLibrary.sessionQuotes

        Group {
            if quotes.isEmpty {
                EmptyView()
            } else if shouldAnimate {
                TimelineView(.periodic(from: .now, by: rotationInterval)) { _ in
                    quoteButton(quotes: quotes, index: displayedIndex(for: quotes.count))
                }
            } else {
                quoteButton(quotes: quotes, index: displayedIndex(for: quotes.count))
            }
        }
        .id(day)
    }

    private var shouldAnimate: Bool {
        !reduceMotion && !voiceOverEnabled && !TestHooks.reduceDecorativeMotion && !TestHooks.disableAnimations
    }

    private func quoteButton(quotes: [DailyHighlightQuote], index: Int) -> some View {
        let quote = quotes[index]

        return Button {
            select(index: (index + 1) % quotes.count)
            MarbleHaptics.selection()
        } label: {
            VStack(alignment: centered ? .center : .leading, spacing: MarbleSpacing.xxs) {
                Text("\(quote.text)")
                    .font(singleLineFont.map { Font($0) } ?? MarbleTypography.rowMeta.italic())
                    .lineLimit(singleLineFont == nil ? nil : 1)
                    .multilineTextAlignment(centered ? .center : .leading)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: singleLineFont != nil, vertical: true)

                if centered {
                    Text(quote.author)
                        .font(MarbleTypography.smallLabel)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .accessibilityHidden(true)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: MarbleSpacing.xs) {
                        Text(quote.author)
                        Spacer(minLength: MarbleSpacing.xs)
                        Text("\(index + 1) / \(quotes.count)")
                            .monospacedDigit()
                    }
                    .font(MarbleTypography.smallLabel)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)
                }
            }
            .id(quote.id)
            .transition(.opacity)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: centered ? .center : .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .highPriorityGesture(
            DragGesture(minimumDistance: 24, coordinateSpace: .local)
                .onEnded { value in
                    guard quotes.count > 1 else { return }
                    select(index: DailyHighlightQuoteRotation.indexAfterSwipe(
                        from: index,
                        quoteCount: quotes.count,
                        dragWidth: Double(value.translation.width)
                    ))
                    MarbleHaptics.selection()
                }
        )
        .animation(shouldAnimate ? .easeInOut(duration: 0.35) : nil, value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(quote.text), \(quote.author). Quote \(index + 1) of \(quotes.count)")
        .accessibilityHint("Shows the next quote. Swipe left or right to move between quotes.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                select(index: (index + 1) % quotes.count)
            case .decrement:
                select(index: (index - 1 + quotes.count) % quotes.count)
            @unknown default:
                break
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    /// Records the pick with the tick it was made in, so
    /// `DailyHighlightQuoteRotation` can hold it for at least one full
    /// interval and then let auto-rotation resume. With rotation off
    /// (VoiceOver, Reduce Motion, tests) the pick is permanent.
    private func select(index: Int) {
        manualSelection = DailyHighlightQuoteRotation.ManualSelection(
            index: index,
            tick: DailyHighlightQuoteRotation.tick(at: AppEnvironment.now, interval: rotationInterval)
        )
    }

    private func displayedIndex(for quoteCount: Int) -> Int {
        DailyHighlightQuoteRotation.displayedIndex(
            quoteCount: quoteCount,
            autoRotates: shouldAnimate,
            manualSelection: manualSelection,
            currentTick: DailyHighlightQuoteRotation.tick(at: AppEnvironment.now, interval: rotationInterval)
        )
    }
}

/// Quiet centered quote footer for the Progress overview first screen: same
/// single-line quotes and 12-second rotation, with a still, minimal
/// treatment — no counter, no card chrome — so it reads as decoration.
struct ProgressQuoteFooter: View {
    let day: Date
    let availableWidth: CGFloat

    @ScaledMetric(relativeTo: .caption) private var quotePointSize: CGFloat = 12
    @Environment(\.legibilityWeight) private var legibilityWeight

    var body: some View {
        let font = ProgressOverviewQuotes.font(
            pointSize: quotePointSize,
            bold: legibilityWeight == .bold
        )
        let quotes = ProgressOverviewQuotes.fitting(
            DailyHighlightQuoteLibrary.sessionQuotes,
            width: availableWidth,
            font: font
        )

        DailyHighlightQuoteRotator(
            day: day,
            centered: true,
            quotePool: quotes,
            singleLineFont: font,
            accessibilityIdentifier: "Trends.Overview.Quote",
            accessibilityLabel: "Training quote"
        )
        .frame(maxWidth: .infinity)
    }
}

/// Measure with the same scaled font the overview renders. Filtering preserves
/// session order, so taps, swipes and automatic rotation only visit fitting quotes.
/// If none fit at the current width/text size, the decorative footer stays empty.
enum ProgressOverviewQuotes {
    static func font(pointSize: CGFloat, bold: Bool = false) -> UIFont {
        let base = UIFont.systemFont(ofSize: pointSize)
        let traits: UIFontDescriptor.SymbolicTraits = bold ? [.traitItalic, .traitBold] : [.traitItalic]
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: pointSize)
    }

    static func fitting(
        _ quotes: [DailyHighlightQuote],
        width: CGFloat,
        font: UIFont
    ) -> [DailyHighlightQuote] {
        guard width.isFinite, width > 2 else { return [] }
        return quotes.filter { quote in
            guard !quote.text.isEmpty,
                  quote.text.rangeOfCharacter(from: .newlines) == nil else { return false }
            let measuredWidth = (quote.text as NSString).size(withAttributes: [.font: font]).width
            // Leave a small rounding allowance for glyph edges and pixel alignment.
            return ceil(measuredWidth) + 2 <= width
        }
    }
}
