import SwiftUI

/// Compact, redundant sprint feedback for list rows and the Quick Log card.
/// Color reinforces the result; symbol + text carry the meaning on their own.
struct SprintGoalStatusLine: View {
    let evaluation: SprintGoalEvaluation
    let snapshot: SprintGoalSnapshot

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                    statusCapsule
                    contextText
                }
            } else {
                HStack(spacing: MarbleSpacing.xs) {
                    statusCapsule
                    contextText
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("SprintGoal.Status")
    }

    private var statusCapsule: some View {
        HStack(spacing: MarbleSpacing.xxxs) {
            Image(systemName: symbolName)
                .accessibilityHidden(true)
            Text(evaluation.status.title)
                .lineLimit(1)
        }
            .font(MarbleTypography.rowMeta.weight(.bold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, MarbleSpacing.xs)
            .padding(.vertical, MarbleSpacing.xxxs)
            .background(statusColor.opacity(colorScheme == .dark ? 0.18 : 0.10))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(statusColor.opacity(0.38), lineWidth: 1)
            }
            .fixedSize(horizontal: true, vertical: true)
    }

    private var contextText: some View {
        Text(contextLabel)
            .font(MarbleTypography.rowMeta.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var contextLabel: String {
        var parts: [String] = []
        if let repetitionNumber = snapshot.repetitionNumber {
            parts.append("Rep \(repetitionNumber)/\(snapshot.repetitionCount)")
        }
        parts.append("\(snapshot.isInferred ? "Current target" : "Target") \(evaluation.targetText)")
        return parts.joined(separator: " · ")
    }

    private var accessibilitySummary: String {
        "\(evaluation.status.title). \(contextLabel). \(evaluation.reason)"
    }

    private var symbolName: String {
        switch evaluation.status {
        case .hit: "checkmark.circle.fill"
        case .missed: "xmark.circle.fill"
        case .notScored: "minus.circle.fill"
        }
    }

    private var statusColor: Color {
        switch evaluation.status {
        case .hit: Theme.sprintGoalHitColor(for: colorScheme)
        case .missed: Theme.sprintGoalMissColor(for: colorScheme)
        case .notScored: Theme.secondaryTextColor(for: colorScheme)
        }
    }
}

/// Read-only explanation shown above editable set metrics.
struct SprintGoalResultCard: View {
    let entry: SetEntry
    let snapshot: SprintGoalSnapshot
    let evaluation: SprintGoalEvaluation

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.m) {
            HStack(alignment: .center, spacing: MarbleSpacing.s) {
                Image(systemName: symbolName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                    Text(evaluation.status.title)
                        .font(MarbleTypography.rowTitle)
                        .foregroundStyle(statusColor)
                    Text(resultSubtitle)
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                    resultMetric(title: "Recorded", value: evaluation.actualText ?? "No time")
                    resultMetric(title: "Target", value: evaluation.targetText)
                }
            } else {
                HStack(alignment: .top, spacing: MarbleSpacing.xl) {
                    resultMetric(title: "Recorded", value: evaluation.actualText ?? "No time")
                    resultMetric(title: "Target", value: evaluation.targetText)
                    Spacer(minLength: 0)
                }
            }

            Text(evaluation.reason)
                .font(MarbleTypography.rowSubtitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .overlay(Theme.subtleDividerColor(for: colorScheme))

            Text(provenanceText)
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, MarbleSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("SetDetail.SprintGoalResult")
    }

    private func resultMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
            Text(title.uppercased())
                .font(MarbleTypography.smallLabel)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
        }
    }

    private var resultSubtitle: String {
        if let repetitionNumber = snapshot.repetitionNumber {
            return "Rep \(repetitionNumber) of \(snapshot.repetitionCount)"
        }
        return snapshot.isInferred ? "Existing sprint rep" : "Sprint rep"
    }

    private var provenanceText: String {
        let distance = Formatters.distance.string(from: NSNumber(value: snapshot.distance)) ?? "\(snapshot.distance)"
        let source = snapshot.isInferred ? "Goal recovered from the exercise's current setup" : "Goal saved when this rep was logged"
        return "\(distance) \(snapshot.distanceUnit.symbol) · \(source)"
    }

    private var accessibilitySummary: String {
        let actual = evaluation.actualText ?? "No recorded time"
        return "\(evaluation.status.title). Recorded \(actual). Target \(evaluation.targetText). \(evaluation.reason). \(provenanceText)."
    }

    private var symbolName: String {
        switch evaluation.status {
        case .hit: "checkmark.circle.fill"
        case .missed: "xmark.circle.fill"
        case .notScored: "minus.circle.fill"
        }
    }

    private var statusColor: Color {
        switch evaluation.status {
        case .hit: Theme.sprintGoalHitColor(for: colorScheme)
        case .missed: Theme.sprintGoalMissColor(for: colorScheme)
        case .notScored: Theme.secondaryTextColor(for: colorScheme)
        }
    }
}
