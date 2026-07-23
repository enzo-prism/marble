import SwiftUI
import TipKit

struct TrendsFocusView: View {
    let snapshot: TrainingConsistency.Snapshot
    @Binding var weeklyTarget: Int
    let report: MonthlyReport?
    let assessments: [LifterCoaching.ProgressionAssessment]
    let onSelectExercise: (UUID) -> Void
    let onOpenReport: (MonthlyReport) -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// Shown once on the priority lift card — the coaching cards read as static
    /// summaries, so the tip points out they're tappable. Tapping any coaching
    /// card (here or in the strength dashboard) invalidates it, per the
    /// `MarbleTips` contract.
    private let coachingTip = CoachingCardsTip()

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                Text("Focus")
                    .font(MarbleTypography.sectionTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityIdentifier("Trends.Focus")
                Text("The few things most worth acting on now.")
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }

            ConsistencyGoalCardView(snapshot: snapshot, weeklyTarget: $weeklyTarget)

            if let priorityAssessment {
                LiftFocusCard(assessment: priorityAssessment) {
                    coachingTip.invalidate(reason: .actionPerformed)
                    onSelectExercise(priorityAssessment.exerciseID)
                }
                .popoverTip(coachingTip)
            }

            if let report {
                MonthlyReportCardView(report: report) {
                    onOpenReport(report)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var priorityAssessment: LifterCoaching.ProgressionAssessment? {
        assessments.sorted { lhs, rhs in
            priority(lhs.verdict) < priority(rhs.verdict)
        }.first
    }

    private func priority(_ verdict: LifterCoaching.ProgressionVerdict) -> Int {
        switch verdict {
        case .adapted: return 0
        case .holding: return 1
        case .progressing: return 2
        case .building: return 3
        }
    }
}

private struct LiftFocusCard: View {
    let assessment: LifterCoaching.ProgressionAssessment
    let onOpen: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: MarbleSpacing.s) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                    Text(assessment.exerciseName)
                        .font(MarbleTypography.rowTitle)
                    Text(message)
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: MarbleSpacing.xs)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)
            }
            .padding(MarbleSpacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .marbleCardBackground(cornerRadius: MarbleCornerRadius.medium)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(assessment.exerciseName). \(message)")
        .accessibilityHint("Show this lift's detailed trends")
        .accessibilityIdentifier("Trends.Focus.Lift")
    }

    private var symbol: String {
        switch assessment.verdict {
        case .progressing: return "arrow.up.right"
        case .adapted: return "arrow.trianglehead.2.clockwise.rotate.90"
        case .holding: return "equal"
        case .building: return "chart.line.uptrend.xyaxis"
        }
    }

    private var message: String {
        switch assessment.verdict {
        case .progressing:
            return "Progressing — keep the current approach."
        case .holding:
            return "Holding steady — review the full trend before changing load."
        case .adapted:
            return "Flat across recent sessions — consider a small progression."
        case .building:
            return "Keep logging to establish a reliable baseline."
        }
    }
}
