import SwiftUI

struct QuickLogCardView: View {
    let entry: SetEntry?
    var prBadge: PersonalRecordBadge = []
    var sprintGoal: SprintGoalSnapshot? = nil
    var bestCue: QuickLogBestCue? = nil
    let onLogAgain: () -> Void
    let onEdit: () -> Void
    let onLogSet: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.m) {
            if let entry {
                populatedContent(for: entry)
            } else {
                emptyContent
            }
        }
        .padding(MarbleSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .marbleCardBackground()
        .accessibilityElement(children: .contain)
    }

    private func populatedContent(for entry: SetEntry) -> some View {
        let summary = summaryLine(for: entry)
        let lastLogged = lastLoggedLine(for: entry)

        return VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            HStack(alignment: .top, spacing: MarbleSpacing.s) {
                VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                    Text(sprintGoal == nil ? "Ready to log" : "Ready to log again")
                        .font(MarbleTypography.smallLabel)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .textCase(.uppercase)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(entry.exercise.name)
                        .font(MarbleTypography.rowTitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if !prBadge.isEmpty {
                        PRBadgeLabel(badge: prBadge)
                    }

                    Text(sprintGoal == nil ? summary : "Last rep · \(summary)")
                        .font(MarbleTypography.rowSubtitle)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .monospacedDigit()
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let bestCue {
                        bestCueLine(bestCue)
                    }

                    if let sprintGoal {
                        SprintGoalStatusLine(
                            evaluation: SprintGoalEvaluation.evaluate(snapshot: sprintGoal, entry: entry),
                            snapshot: sprintGoal
                        )
                    }

                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel(for: entry, summary: summary, lastLogged: lastLogged))

                Spacer(minLength: MarbleSpacing.xs)

                ExerciseIconView(exercise: entry.exercise, fontSize: 17, frameSize: 28)
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: MarbleSpacing.xs) {
                    logAgainButton
                    editButton
                }
            } else {
                HStack(spacing: MarbleSpacing.xs) {
                    logAgainButton
                    editButton
                }
            }
        }
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: MarbleSpacing.xs) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(title)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }

    private func bestCueLine(_ cue: QuickLogBestCue) -> some View {
        ViewThatFits(in: .horizontal) {
            Text(cue.text)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: MarbleSpacing.xxxs) {
                Text(cue.title)
                Text(cue.value)
                    .fontWeight(.semibold)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .font(MarbleTypography.rowMeta.weight(.medium))
        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        .monospacedDigit()
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            HStack(alignment: .top, spacing: MarbleSpacing.s) {
                VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                    Text("Start today")
                        .font(MarbleTypography.smallLabel)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .textCase(.uppercase)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Log your first set")
                        .font(MarbleTypography.rowTitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                    Text("One quick entry is enough to start your history.")
                        .font(MarbleTypography.rowSubtitle)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: MarbleSpacing.xs)

                ScaledSymbol(systemName: "plus.circle", size: 24, weight: .semibold)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)
            }

            Button {
                onLogSet()
            } label: {
                actionLabel("Log Set", systemImage: "plus")
            }
            .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true, prominence: .primary))
            .accessibilityElement(children: .ignore)
        .accessibilityLabel("Log Set")
        .accessibilityIdentifier("Journal.QuickLog.EmptyLogSet")
    }
    }

    private var logAgainButton: some View {
        Button {
            onLogAgain()
        } label: {
            actionLabel("Log Again", systemImage: "plus")
        }
        .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true, prominence: .primary))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Log Again")
        .accessibilityIdentifier("Journal.QuickLog.LogAgain")
    }

    private var editButton: some View {
        Button {
            onEdit()
        } label: {
            actionLabel("Edit", systemImage: "pencil")
        }
        .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Edit")
        .accessibilityIdentifier("Journal.QuickLog.Edit")
    }

    private func summaryLine(for entry: SetEntry) -> String {
        var parts: [String] = []
        if let weight = entry.weight {
            let formattedWeight = entry.exercise.formattedWeightSummary(weight, unit: entry.weightUnit)
            if let reps = entry.reps {
                parts.append("\(formattedWeight) × \(reps)")
            } else {
                parts.append(formattedWeight)
            }
        }

        if entry.weight == nil, let reps = entry.reps {
            parts.append("\(reps) reps")
        }

        if let distance = entry.distance {
            parts.append(entry.exercise.formattedDistanceSummary(distance, unit: entry.distanceUnit))
        }

        if let duration = entry.durationSeconds {
            parts.append(DateHelper.formattedDuration(seconds: duration))
        }

        if parts.isEmpty {
            return "No metrics"
        }

        return parts.joined(separator: " · ")
    }

    private func lastLoggedLine(for entry: SetEntry) -> String {
        let day = DateHelper.dayLabel(for: entry.performedAt)
        let time = Formatters.time.string(from: entry.performedAt)
        return "Last logged \(day) at \(time)"
    }

    private func accessibilityLabel(for entry: SetEntry, summary: String, lastLogged: String) -> String {
        let prefix = prBadge.isEmpty ? "" : "\(prBadge.accessibilityDescription). "
        let best = bestCue.map { "\($0.accessibilityLabel), " } ?? ""
        if let sprintGoal {
            let evaluation = SprintGoalEvaluation.evaluate(snapshot: sprintGoal, entry: entry)
            return "\(prefix)\(entry.exercise.name), \(summary), \(best)\(evaluation.status.title), target \(evaluation.targetText), \(evaluation.reason), \(lastLogged)"
        }
        return "\(prefix)\(entry.exercise.name), \(summary), \(best)\(lastLogged)"
    }
}
