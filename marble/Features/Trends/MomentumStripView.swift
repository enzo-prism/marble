import SwiftUI

/// A lightweight ribbon of insight chips shown above the Trends charts: period-over-period
/// deltas, a training streak, and a freshly set personal record.
struct MomentumStripView: View {
    let summary: MomentumSummary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                    chips
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MarbleSpacing.xs) {
                        chips
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("Trends.Momentum")
    }

    @ViewBuilder
    private var chips: some View {
        ForEach(summary.deltas) { delta in
            if delta.changeText != nil {
                MomentumChip(
                    icon: icon(for: delta.direction),
                    title: delta.title,
                    value: delta.valueText,
                    trailing: delta.changeText,
                    accent: accent(for: delta.direction)
                )
            }
        }

        if summary.streakDays >= StreakBuilder.minimumStreakDays {
            MomentumChip(
                icon: "flame.fill",
                title: "Streak",
                value: summary.streakDays == 1 ? "1 day" : "\(summary.streakDays) days",
                trailing: nil,
                accent: .neutral
            )
        }

        if let recentPR = summary.recentPR {
            MomentumChip(
                icon: "trophy.fill",
                title: "New PR",
                value: recentPR.metricTitle,
                trailing: nil,
                accent: .positive
            )
        }
    }

    private func icon(for direction: MomentumDelta.Direction) -> String {
        switch direction {
        case .up:
            return "arrow.up.right"
        case .down:
            return "arrow.down.right"
        case .flat:
            return "minus"
        }
    }

    private func accent(for direction: MomentumDelta.Direction) -> MomentumChip.Accent {
        switch direction {
        case .up:
            return .positive
        case .down, .flat:
            return .neutral
        }
    }

    private var accessibilityLabel: String {
        var parts: [String] = summary.deltas.filter { $0.changeText != nil }.map(\.accessibilityText)
        if summary.streakDays >= StreakBuilder.minimumStreakDays {
            let dayWord = summary.streakDays == 1 ? "day" : "days"
            parts.append("\(summary.streakDays) \(dayWord) training streak")
        }
        if let recentPR = summary.recentPR {
            parts.append(recentPR.accessibilityText)
        }
        return "Momentum. " + parts.joined(separator: ". ")
    }
}

private struct MomentumChip: View {
    enum Accent {
        case positive
        case neutral
    }

    let icon: String
    let title: String
    let value: String
    let trailing: String?
    let accent: Accent

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: MarbleSpacing.xs) {
            Image(systemName: icon)
                .font(MarbleTypography.smallLabel)
                .foregroundStyle(accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                Text(title.uppercased())
                    .font(MarbleTypography.smallLabel)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                HStack(alignment: .firstTextBaseline, spacing: MarbleSpacing.xxs) {
                    Text(value)
                        .font(MarbleTypography.rowTitle)
                        .monospacedDigit()
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                    if let trailing {
                        Text(trailing)
                            .font(MarbleTypography.smallLabel)
                            .monospacedDigit()
                            .foregroundStyle(accentColor)
                    }
                }
            }
        }
        .padding(.horizontal, MarbleSpacing.s)
        .padding(.vertical, MarbleSpacing.xs)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.surfaceColor(for: colorScheme))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Theme.subtleDividerColor(for: colorScheme), lineWidth: 0.75)
        )
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
    }

    private var accentColor: Color {
        switch accent {
        case .positive:
            return Theme.toggleOnColor
        case .neutral:
            return Theme.secondaryTextColor(for: colorScheme)
        }
    }
}
