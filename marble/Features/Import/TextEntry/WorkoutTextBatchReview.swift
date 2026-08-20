import SwiftUI

/// Health-style multi-select list for a paste that split into more than one workout.
struct WorkoutTextBatchReview: View {
    var viewModel: WorkoutTextEntryViewModel
    var onReview: (UUID) -> Void
    var onImport: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        List {
            Section {
                Text(summaryLine)
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                ForEach(viewModel.sessions) { session in
                    sessionRow(session)
                }
            } header: {
                SectionHeaderView(title: "Workouts")
            } footer: {
                if viewModel.alreadyImportedSessionCount > 0 {
                    Text("\(viewModel.alreadyImportedSessionCount) already in your journal — they stay unselected.")
                        .font(MarbleTypography.caption)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
            }

            if viewModel.newExerciseCount > 0 {
                Section {
                    Text("\(viewModel.newExerciseCount) new exercise\(viewModel.newExerciseCount == 1 ? "" : "s") will be added to your library.")
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .accessibilityIdentifier("TextEntry.NewExerciseSummary")
                }
            }

            if let message = viewModel.errorMessage {
                Section {
                    Text(message)
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .accessibilityIdentifier("TextEntry.Error")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
        .safeAreaInset(edge: .bottom) {
            Button {
                onImport()
            } label: {
                Text(importTitle)
            }
            .buttonStyle(MarbleActionButtonStyle(
                isEnabledOverride: !viewModel.importableSelectedSessions.isEmpty,
                expandsHorizontally: true,
                prominence: .primary
            ))
            .disabled(viewModel.importableSelectedSessions.isEmpty)
            .padding(.horizontal, MarbleSpacing.m)
            .padding(.bottom, MarbleSpacing.s)
            .accessibilityIdentifier("TextEntry.Batch.Import")
        }
    }

    private var summaryLine: String {
        let total = viewModel.sessions.count
        let selected = viewModel.selectedSessionCount
        let sets = viewModel.selectedSetCount
        return "\(selected) of \(total) workout\(total == 1 ? "" : "s") selected · \(sets) set\(sets == 1 ? "" : "s")"
    }

    private var importTitle: String {
        let workouts = viewModel.selectedSessionCount
        let sets = viewModel.selectedSetCount
        guard workouts > 0 else { return "Add to Journal" }
        return "Add \(workouts) workout\(workouts == 1 ? "" : "s") (\(sets) set\(sets == 1 ? "" : "s"))"
    }

    @ViewBuilder
    private func sessionRow(_ session: WorkoutImportSession) -> some View {
        HStack(alignment: .top, spacing: MarbleSpacing.s) {
            Button {
                viewModel.toggleSessionSelected(session.id)
            } label: {
                Image(systemName: session.alreadyImported
                      ? "checkmark.circle"
                      : (session.selected ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
            .buttonStyle(.plain)
            .disabled(session.alreadyImported)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(session.draft.title)
            .accessibilityValue(session.alreadyImported
                ? "Already in your journal"
                : (session.selected ? "Selected" : "Not selected"))
            .accessibilityIdentifier("TextEntry.Session.Toggle.\(session.id.uuidString)")

            Button {
                onReview(session.id)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.draft.title)
                        .font(MarbleTypography.rowTitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    Text(detailLine(session))
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    if let match = viewModel.matchBreakdown(for: session).line {
                        Text(match)
                            .font(MarbleTypography.caption)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                            .accessibilityIdentifier("TextEntry.Session.Match.\(session.id.uuidString)")
                    }
                    if session.alreadyImported {
                        Text("Already in your journal")
                            .font(MarbleTypography.caption)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    } else if !session.unparsedLines.isEmpty {
                        Text("\(session.unparsedLines.count) line\(session.unparsedLines.count == 1 ? "" : "s") need review")
                            .font(MarbleTypography.caption)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Review \(session.draft.title)")
            .accessibilityIdentifier("TextEntry.Session.\(session.id.uuidString)")
        }
        .marbleRowInsets()
        .listRowBackground(Theme.backgroundColor(for: colorScheme))
    }

    private func detailLine(_ session: WorkoutImportSession) -> String {
        var parts: [String] = []
        if let date = session.draft.performedAt {
            parts.append(Formatters.day.string(from: date))
        }
        let exercises = session.draft.importableExercises.count
        let sets = session.draft.totalSetCount
        parts.append("\(exercises) exercise\(exercises == 1 ? "" : "s")")
        parts.append("\(sets) set\(sets == 1 ? "" : "s")")
        if session.kind != .typedText {
            parts.append(session.kind.originName)
        }
        return parts.joined(separator: " · ")
    }
}
