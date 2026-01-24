import SwiftUI

struct TrendTooltipView: View {
    let title: String
    let valueText: String
    let summaryText: String?
    let showsPR: Bool
    let viewSetsLabel: String
    let viewSetsAccessibilityLabel: String
    let viewSetsIdentifier: String
    let onViewSets: () -> Void
    let onClear: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(MarbleTypography.rowSubtitle)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                    Spacer()

                    if let onClear {
                        Button("Clear") {
                            onClear()
                        }
                        .font(MarbleTypography.smallLabel)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .accessibilityLabel("Clear selection")
                    }
                }

                HStack(spacing: MarbleSpacing.xxs) {
                    Text(valueText)
                        .font(MarbleTypography.rowTitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                    if showsPR {
                        Image(systemName: "trophy.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                            .accessibilityHidden(true)
                    }
                }

                if let summaryText {
                    Text(summaryText)
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilitySummary)

            Button(viewSetsLabel) {
                onViewSets()
            }
            .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true))
            .accessibilityLabel(viewSetsAccessibilityLabel)
            .accessibilityIdentifier(viewSetsIdentifier)
        }
        .accessibilityElement(children: .contain)
        .padding(MarbleSpacing.s)
        .background(Theme.backgroundColor(for: colorScheme))
        .simultaneousGesture(
            TapGesture().onEnded {
                guard TestHooks.isUITesting, !TestHooks.isAccessibilityAudit else { return }
                onViewSets()
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                .stroke(Theme.dividerColor(for: colorScheme), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous))
    }

    private var accessibilitySummary: String {
        var parts = [title, valueText]
        if let summaryText {
            parts.append(summaryText)
        }
        if showsPR {
            parts.append("Personal record")
        }
        return parts.joined(separator: ", ")
    }
}
