import SwiftUI

/// A compact two-stat card surfacing the user's current and best daily training streaks.
/// Lives at the top of the Calendar tab. Monochrome to match the Marble brand — the flame
/// and trophy glyphs render in the standard grey/ink palette, never tinted.
struct StreakSummaryView: View {
    let summary: StreakSummary

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: MarbleSpacing.s) {
                    currentStat
                    Divider()
                        .overlay(Theme.subtleDividerColor(for: colorScheme))
                    bestStat
                }
            } else {
                HStack(alignment: .top, spacing: MarbleSpacing.s) {
                    currentStat
                    Divider()
                        .overlay(Theme.subtleDividerColor(for: colorScheme))
                    bestStat
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(MarbleSpacing.m)
        .frame(maxWidth: .infinity)
        .marbleCardBackground()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("Calendar.Streak")
    }

    private var currentStat: some View {
        StreakStat(
            icon: "flame.fill",
            label: "Current Streak",
            value: summary.current,
            caption: currentCaption,
            isProminent: true
        )
    }

    private var bestStat: some View {
        StreakStat(
            icon: "trophy.fill",
            label: "Best Streak",
            value: summary.best,
            caption: bestCaption,
            isProminent: false
        )
    }

    private var currentCaption: String {
        if summary.current == 0 {
            return "Log a set to start"
        }
        if summary.loggedToday {
            return "Logged today"
        }
        return "Log today to keep it"
    }

    private var bestCaption: String {
        if summary.best > 0, summary.current == summary.best {
            return "At your best"
        }
        return "All-time best"
    }
}

private struct StreakStat: View {
    let icon: String
    let label: String
    let value: Int
    let caption: String
    let isProminent: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
            Text(label.uppercased())
                .font(MarbleTypography.smallLabel)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: MarbleSpacing.xs) {
                Image(systemName: icon)
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(
                        isProminent
                            ? Theme.primaryTextColor(for: colorScheme)
                            : Theme.secondaryTextColor(for: colorScheme)
                    )
                    .accessibilityHidden(true)

                HStack(alignment: .firstTextBaseline, spacing: MarbleSpacing.xxs) {
                    Text("\(value)")
                        .font(MarbleTypography.screenTitle)
                        .monospacedDigit()
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                    Text(unit)
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
            }

            Text(caption)
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value) \(unit), \(caption)")
    }

    private var unit: String {
        value == 1 ? "day" : "days"
    }
}
