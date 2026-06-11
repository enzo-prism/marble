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
                    titleText

                    Spacer()

                    clearSelectionButton
                }

                HStack(alignment: .firstTextBaseline, spacing: MarbleSpacing.xxs) {
                    Text(valueText)
                        .font(MarbleTypography.rowTitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    if showsPR {
                        Image(systemName: "trophy.fill")
                            .font(.caption2)
                            .foregroundStyle(TrendsPalette.personalRecord.color(for: colorScheme))
                            .accessibilityHidden(true)
                    }
                }

                if let summaryText {
                    Text(summaryText)
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilitySummary)

            Button(viewSetsLabel) {
                onViewSets()
            }
            .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true, prominence: .primary))
            .accessibilityLabel(viewSetsAccessibilityLabel)
            .accessibilityIdentifier(viewSetsIdentifier)
        }
        .accessibilityElement(children: .contain)
        .padding(MarbleSpacing.s)
        .marbleCardBackground(cornerRadius: MarbleCornerRadius.medium)
        .simultaneousGesture(
            TapGesture().onEnded {
                guard TestHooks.isUITesting, !TestHooks.isAccessibilityAudit else { return }
                onViewSets()
            }
        )
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

    private var titleText: some View {
        Text(title)
            .font(MarbleTypography.rowSubtitle)
            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var clearSelectionButton: some View {
        if let onClear {
            Button("Clear") {
                onClear()
            }
            .font(MarbleTypography.smallLabel)
            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            .frame(minHeight: MarbleLayout.chipMinHeight, alignment: .trailing)
            .padding(.horizontal, MarbleSpacing.xxs)
            .contentShape(Rectangle())
            .accessibilityLabel("Clear selection")
            .accessibilityIdentifier("\(viewSetsIdentifier).Clear")
        }
    }
}
