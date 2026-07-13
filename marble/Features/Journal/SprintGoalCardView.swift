import SwiftUI

struct SprintGoalCardView: View {
    let prescription: SprintPrescriptionPlan
    let distanceUnit: DistanceUnit
    let restSeconds: Int
    let completedRepetitions: Int
    let actualSeconds: Int?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            HStack {
                VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                    Text(repTitle)
                        .font(MarbleTypography.rowTitle)
                    Text(prescription.summary(distanceUnit: distanceUnit, restSeconds: restSeconds))
                        .font(MarbleTypography.rowSubtitle)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "figure.run")
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)
            }

            if let actualSeconds,
               let outcome = prescription.outcome(for: actualSeconds) {
                Divider()
                Text(outcome.title)
                    .font(MarbleTypography.rowSubtitle.weight(.semibold))
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityIdentifier("AddSet.Sprint.GoalStatus")
            }
        }
        .padding(MarbleSpacing.m)
        .marbleCardBackground()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("AddSet.Sprint.Prescription")
    }

    private var repTitle: String {
        let next = completedRepetitions + 1
        if next <= prescription.repetitionCount {
            return "Rep \(next) of \(prescription.repetitionCount)"
        }
        return "Extra rep \(next)"
    }
}
