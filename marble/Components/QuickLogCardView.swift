import SwiftUI

struct QuickLogCardView: View {
    let entry: SetEntry?
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
                    Text("Ready to log")
                        .font(MarbleTypography.smallLabel)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .textCase(.uppercase)

                    Text(entry.exercise.name)
                        .font(MarbleTypography.rowTitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(summary)
                        .font(MarbleTypography.rowSubtitle)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .monospacedDigit()
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(entry.exercise.name), \(summary), \(lastLogged)")

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

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            HStack(alignment: .top, spacing: MarbleSpacing.s) {
                VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                    Text("Start today")
                        .font(MarbleTypography.smallLabel)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .textCase(.uppercase)

                    Text("Log your first set")
                        .font(MarbleTypography.rowTitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

                    Text("One quick entry is enough to start your history.")
                        .font(MarbleTypography.rowSubtitle)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: MarbleSpacing.xs)

                Image(systemName: "plus.circle")
                    .font(.system(size: 24, weight: .semibold))
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
            let formattedWeight = Formatters.weight.string(from: NSNumber(value: weight)) ?? "\(weight)"
            if let reps = entry.reps {
                parts.append("\(formattedWeight) \(entry.weightUnit.symbol) × \(reps)")
            } else {
                parts.append("\(formattedWeight) \(entry.weightUnit.symbol)")
            }
        }

        if entry.weight == nil, let reps = entry.reps {
            parts.append("\(reps) reps")
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
}
