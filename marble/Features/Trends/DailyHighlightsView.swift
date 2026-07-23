import SwiftUI

struct DailyHighlightsSection: View {
    let summary: DailyHighlightSummary
    let occurrence: DailyHighlightOccurrence
    let onCustomize: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            sectionHeader
            DailyHighlightsCard(summary: summary)
        }
    }

    @ViewBuilder
    private var sectionHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                sectionTitle
                customizeButton
            }
        } else {
            HStack(alignment: .center, spacing: MarbleSpacing.s) {
                sectionTitle
                Spacer(minLength: MarbleSpacing.xs)
                customizeButton
            }
        }
    }

    private var sectionTitle: some View {
        Text("Daily Highlights")
            .font(MarbleTypography.sectionTitle)
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("Trends.DailyHighlights")
    }

    private var customizeButton: some View {
        Button(action: onCustomize) {
            Label(expiryText, systemImage: "clock")
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityLabel("Customize Daily Highlights window")
        .accessibilityValue(expiryText)
        .accessibilityIdentifier("Trends.DailyHighlights.Customize")
    }

    private var expiryText: String {
        "Until \(occurrence.interval.end.addingTimeInterval(-1).formatted(date: .omitted, time: .shortened))"
    }
}

private struct DailyHighlightsCard: View {
    let summary: DailyHighlightSummary

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.l) {
            cardHeader

            Text(summary.headline)
                .font(.title2.weight(.bold))
                .foregroundStyle(primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: MarbleSpacing.m) {
                ForEach(Array(summary.achievements.enumerated()), id: \.element.id) { index, achievement in
                    DailyHighlightAchievementView(achievement: achievement, index: index)

                    if index < summary.achievements.count - 1 {
                        Rectangle()
                            .fill(divider)
                            .frame(height: 0.5)
                            .accessibilityHidden(true)
                    }
                }
            }

            Rectangle()
                .fill(divider)
                .frame(height: 0.5)
                .accessibilityHidden(true)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: MarbleSpacing.s) { stats }
                } else {
                    HStack(alignment: .top, spacing: MarbleSpacing.s) { stats }
                }
            }

            Rectangle()
                .fill(divider)
                .frame(height: 0.5)
                .accessibilityHidden(true)

            DailyHighlightQuoteRotator(day: summary.day, accent: accent)
        }
        .padding(MarbleSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MarbleCornerRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MarbleCornerRadius.large, style: .continuous)
                .stroke(accent.opacity(colorScheme == .dark ? 0.58 : 0.46), lineWidth: 0.75)
        }
        .overlay(alignment: .top) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [accent, companionAccent],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 3)
                .padding(.horizontal, MarbleSpacing.l)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var cardHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            dayLabel
        } else {
            HStack(alignment: .firstTextBaseline, spacing: MarbleSpacing.s) {
                dayLabel
                Spacer(minLength: MarbleSpacing.xs)
                Text("marble")
                    .font(MarbleTypography.rowMeta.weight(.semibold))
                    .foregroundStyle(primary)
                    .accessibilityHidden(true)
            }
        }
    }

    private var dayLabel: some View {
        Label(dayEyebrow, systemImage: "sparkles")
            .font(MarbleTypography.smallLabel)
            .tracking(0.8)
            .foregroundStyle(primary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var stats: some View {
        ForEach(summary.stats.prefix(3)) { stat in
            VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                Text(stat.value)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(stat.label.uppercased())
                    .font(MarbleTypography.smallLabel)
                    .tracking(0.5)
                    .foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(stat.value) \(stat.label)")
        }
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: MarbleCornerRadius.large, style: .continuous)
                .fill(Theme.surfaceColor(for: colorScheme))

            if !reduceTransparency && !TestHooks.forceReduceTransparency {
                RadialGradient(
                    colors: [
                        accent.opacity(colorScheme == .dark ? 0.24 : 0.16),
                        companionAccent.opacity(colorScheme == .dark ? 0.10 : 0.06),
                        .clear
                    ],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 340
                )
            }
        }
    }

    private var accent: Color {
        switch summary.achievements.first?.kind {
        case .personalRecord: TrendsPalette.personalRecord.color(for: colorScheme)
        case .runBest: TrendsPalette.supplements.color(for: colorScheme)
        case .liftProgress: TrendsPalette.progress.color(for: colorScheme)
        case .dailyBest, nil: TrendsPalette.consistency.color(for: colorScheme)
        }
    }

    private var companionAccent: Color {
        switch summary.achievements.first?.kind {
        case .personalRecord: TrendsPalette.volumeWeighted.color(for: colorScheme)
        case .runBest: TrendsPalette.consistency.color(for: colorScheme)
        case .liftProgress: TrendsPalette.personalRecord.color(for: colorScheme)
        case .dailyBest, nil: TrendsPalette.progress.color(for: colorScheme)
        }
    }

    private var primary: Color { Theme.primaryTextColor(for: colorScheme) }
    private var secondary: Color { Theme.secondaryTextColor(for: colorScheme) }
    private var divider: Color { accent.opacity(colorScheme == .dark ? 0.30 : 0.22) }

    private var dayEyebrow: String {
        "TODAY · \(summary.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())"
    }
}

private struct DailyHighlightAchievementView: View {
    let achievement: DailyHighlightAchievement
    let index: Int

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                    icon
                    achievementText
                }
            } else {
                HStack(alignment: .top, spacing: MarbleSpacing.s) {
                    icon
                    achievementText
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(achievement.accessibilityLabel)
        .accessibilityIdentifier("Trends.DailyHighlights.Achievement.\(index)")
    }

    private var icon: some View {
        Image(systemName: achievement.kind.systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(accent)
            .frame(width: 38, height: 38)
            .background(accent.opacity(colorScheme == .dark ? 0.18 : 0.12), in: Circle())
            .accessibilityHidden(true)
    }

    private var achievementText: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
            Text(achievement.title.uppercased())
                .font(MarbleTypography.smallLabel)
                .tracking(0.6)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            Text(achievement.value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            Text(achievement.detail)
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accent: Color {
        switch achievement.kind {
        case .personalRecord: TrendsPalette.personalRecord.color(for: colorScheme)
        case .runBest: TrendsPalette.supplements.color(for: colorScheme)
        case .liftProgress: TrendsPalette.progress.color(for: colorScheme)
        case .dailyBest: TrendsPalette.consistency.color(for: colorScheme)
        }
    }
}

private struct DailyHighlightQuoteRotator: View {
    let day: Date
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var manuallySelectedIndex: Int?

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

    @Environment(\.colorScheme) private var colorScheme

    private var shouldAnimate: Bool {
        !reduceMotion && !voiceOverEnabled && !TestHooks.reduceDecorativeMotion && !TestHooks.disableAnimations
    }

    private func quoteButton(quotes: [DailyHighlightQuote], index: Int) -> some View {
        let quote = quotes[index]

        return Button {
            manuallySelectedIndex = (index + 1) % quotes.count
            MarbleHaptics.selection()
        } label: {
            VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: MarbleSpacing.xs) {
                    Image(systemName: "quote.opening")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                        .accessibilityHidden(true)

                    Text("EVENING NOTE")
                        .font(MarbleTypography.smallLabel)
                        .tracking(0.7)
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                    Text("“\(quote.text)”")
                        .font(.callout.weight(.medium))
                        .fontDesign(.serif)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("— \(quote.author)")
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .id(quote.id)
                .transition(.opacity)

                HStack(spacing: MarbleSpacing.xxs) {
                    ForEach(quotes.indices, id: \.self) { quoteIndex in
                        Capsule()
                            .fill(quoteIndex == index ? accent : accent.opacity(0.24))
                            .frame(width: quoteIndex == index ? 16 : 6, height: 6)
                    }
                }
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(shouldAnimate ? .easeInOut(duration: 0.35) : nil, value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Daily motivation")
        .accessibilityValue("\(quote.text), \(quote.author). Quote \(index + 1) of \(quotes.count)")
        .accessibilityHint("Shows the next quote.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                manuallySelectedIndex = (index + 1) % quotes.count
            case .decrement:
                manuallySelectedIndex = (index - 1 + quotes.count) % quotes.count
            @unknown default:
                break
            }
        }
        .accessibilityIdentifier("Trends.DailyHighlights.Quote")
    }

    private func displayedIndex(for quoteCount: Int) -> Int {
        if let manuallySelectedIndex {
            return manuallySelectedIndex % quoteCount
        }
        guard shouldAnimate else { return 0 }
        return Int(AppEnvironment.now.timeIntervalSinceReferenceDate / rotationInterval) % quoteCount
    }
}
