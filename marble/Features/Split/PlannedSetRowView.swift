import SwiftUI
import SwiftData

struct PlannedSetRowView: View {
    let plannedSet: PlannedSet

    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \SprintPrescription.createdAt) private var sprintPrescriptions: [SprintPrescription]

    var body: some View {
        HStack(alignment: .top, spacing: MarbleLayout.rowSpacing) {
            ExerciseIconView(exercise: plannedSet.exercise, fontSize: 18, frameSize: MarbleLayout.rowIconSize)

            VStack(alignment: .leading, spacing: MarbleLayout.rowInnerSpacing) {
                Text(plannedSet.exercise.name)
                    .font(MarbleTypography.rowTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                Text(subtitle)
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }

            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(plannedSet.exercise.name), planned set")
    }

    private var subtitle: String {
        if let prescription = sprintPrescriptions.first(where: { $0.exerciseID == plannedSet.exercise.id }) {
            return prescription.summary(
                distanceUnit: plannedSet.exercise.preferredDistanceUnit,
                restSeconds: plannedSet.exercise.defaultRestSeconds
            )
        }
        let trimmed = plannedSet.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Planned set" : trimmed
    }
}
