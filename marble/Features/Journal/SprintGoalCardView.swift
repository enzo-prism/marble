import SwiftUI

struct SprintGoalCardView: View {
    let variant: SprintVariantValue
    /// The exercise's other loggable variants; a menu appears when the athlete
    /// has more than one plan to pick from.
    let allVariants: [SprintVariantValue]
    let restSeconds: Int
    let completedRepetitions: Int
    /// Live tenths from the logger's time field / stopwatch, for the inline
    /// outcome preview.
    let actualTenths: Int?
    /// Hit-rate-driven coaching line ("Hit 2 sessions straight — try 8.3s"),
    /// computed by `SprintProgression`.
    let progressionHint: String?
    let onSelectVariant: (SprintVariantValue) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            HStack {
                VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                    Text(repTitle)
                        .font(MarbleTypography.rowTitle)
                    Text(variant.summary(restSeconds: restSeconds))
                        .font(MarbleTypography.rowSubtitle)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "figure.run")
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)
            }

            if allVariants.count > 1 {
                variantMenu
            }

            if let actualTenths,
               let outcome = variant.target.outcome(forTenths: actualTenths) {
                Divider()
                Text(outcome.title)
                    .font(MarbleTypography.rowSubtitle.weight(.semibold))
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityIdentifier("AddSet.Sprint.GoalStatus")
            }

            if let progressionHint {
                Divider()
                Label(progressionHint, systemImage: "chart.line.uptrend.xyaxis")
                    .font(MarbleTypography.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("AddSet.Sprint.ProgressionHint")
            }
        }
        .padding(MarbleSpacing.m)
        .marbleCardBackground()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("AddSet.Sprint.Prescription")
    }

    private var variantMenu: some View {
        Menu {
            ForEach(allVariants) { candidate in
                Button {
                    onSelectVariant(candidate)
                } label: {
                    if candidate.id == variant.id {
                        Label(candidate.displayName, systemImage: "checkmark")
                    } else {
                        Text(candidate.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: MarbleSpacing.xs) {
                Text("Plan: \(variant.displayName)")
                    .font(MarbleTypography.rowSubtitle.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Sprint plan, \(variant.displayName)")
        .accessibilityHint("Chooses which sprint plan this rep is logged against.")
        .accessibilityIdentifier("AddSet.Sprint.VariantPicker")
    }

    private var repTitle: String {
        let next = completedRepetitions + 1
        if next <= variant.repetitionCount {
            return "Rep \(next) of \(variant.repetitionCount)"
        }
        return "Extra rep \(next)"
    }
}
