import SwiftUI

/// The rollup shown after the final prescribed rep: the payoff moment the
/// sheet's silent close used to swallow. Pure display over the sequence the
/// logger tracked — nothing here re-queries or re-saves.
struct SprintSequenceSummaryView: View {
    let variant: SprintVariantValue
    let outcomes: [SprintRepOutcome]

    @Environment(\.colorScheme) private var colorScheme

    private var hits: Int { outcomes.filter(\.isHit).count }
    private var bestTenths: Int? { outcomes.map(\.tenths).min() }
    private var averageTenths: Int? {
        guard !outcomes.isEmpty else { return nil }
        let total = outcomes.reduce(0) { $0 + $1.tenths }
        return Int((Double(total) / Double(outcomes.count)).rounded())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MarbleSpacing.l) {
                VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                    Text(variant.displayName)
                        .font(MarbleTypography.sectionTitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    Text("Target \(variant.target.targetText())")
                        .font(MarbleTypography.rowSubtitle)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }

                HStack(spacing: MarbleSpacing.m) {
                    statTile(
                        title: "Hits",
                        value: "\(hits)/\(outcomes.count)",
                        identifier: "SprintSummary.Hits"
                    )
                    if let bestTenths {
                        statTile(
                            title: "Best",
                            value: SprintTiming.text(tenths: bestTenths),
                            identifier: "SprintSummary.Best"
                        )
                    }
                    if let averageTenths {
                        statTile(
                            title: "Average",
                            value: SprintTiming.text(tenths: averageTenths),
                            identifier: "SprintSummary.Average"
                        )
                    }
                }

                VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                    ForEach(Array(outcomes.enumerated()), id: \.offset) { index, rep in
                        HStack(spacing: MarbleSpacing.s) {
                            Image(systemName: rep.isHit ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(rep.isHit
                                    ? Theme.sprintGoalHitColor(for: colorScheme)
                                    : Theme.sprintGoalMissColor(for: colorScheme))
                                .accessibilityHidden(true)
                            Text("Rep \(index + 1)")
                                .font(MarbleTypography.rowSubtitle)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                            Spacer()
                            Text(SprintTiming.text(tenths: rep.tenths))
                                .font(MarbleTypography.rowSubtitle.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Rep \(index + 1), \(SprintTiming.text(tenths: rep.tenths)), \(rep.isHit ? "goal hit" : "goal missed")")
                    }
                }
                .padding(MarbleSpacing.m)
                .marbleCardBackground()
            }
            .padding(MarbleSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.backgroundColor(for: colorScheme))
        .accessibilityIdentifier("AddSet.SprintSummary")
    }

    private func statTile(title: String, value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
            Text(title)
                .font(MarbleTypography.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            Text(value)
                .font(MarbleTypography.sectionTitle)
                .monospacedDigit()
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
        }
        .padding(MarbleSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .marbleCardBackground()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
        .accessibilityIdentifier(identifier)
    }
}
