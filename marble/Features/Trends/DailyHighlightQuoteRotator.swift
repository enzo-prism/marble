import SwiftUI

/// Auto-rotating training quote, shared by the Daily Highlights card and the
/// Progress overview footer. Quotes come from `DailyHighlightQuoteLibrary` (one
/// stable 3-quote cohort per day); the schedule and tap-to-hold semantics live
/// in `DailyHighlightQuoteRotation`. Pass `centered` for the quiet overview
/// footer treatment (centered text, no counter); the default leading layout
/// with counter is the Daily Highlights card style.
struct DailyHighlightQuoteRotator: View {
    let day: Date
    var centered: Bool = false
    var accessibilityIdentifier: String = "Trends.DailyHighlights.Quote"
    var accessibilityLabel: String = "Daily motivation"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var manualSelection: DailyHighlightQuoteRotation.ManualSelection?

    private let rotationInterval: TimeInterval = 12

    var body: some View {
        let quotes = DailyHighlightQuoteLibrary.quotes(for: day)

        Group {
            if shouldAnimate {
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
                    .font(MarbleTypography.rowMeta)
                    .italic()
                    .multilineTextAlignment(centered ? .center : .leading)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

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
        .animation(shouldAnimate ? .easeInOut(duration: 0.35) : nil, value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(quote.text), \(quote.author). Quote \(index + 1) of \(quotes.count)")
        .accessibilityHint("Shows the next quote.")
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
/// quotes and 12-second rotation as Daily Highlights, but a still, minimal
/// treatment — no counter, no card chrome — so it reads as decoration.
struct ProgressQuoteFooter: View {
    let day: Date

    var body: some View {
        DailyHighlightQuoteRotator(
            day: day,
            centered: true,
            accessibilityIdentifier: "Trends.Overview.Quote",
            accessibilityLabel: "Training quote"
        )
        .padding(.top, MarbleSpacing.xxl)
        .frame(maxWidth: .infinity)
    }
}
