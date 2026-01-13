import SwiftUI
import SwiftData

struct SplitDayEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var quickLog: QuickLogCoordinator

    @Bindable var day: SplitDay

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var showNotes = false
    @State private var showExercisePicker = false
    @State private var selectedExercise: Exercise?

    var body: some View {
        List {
            Section {
                if orderedPlannedSets.isEmpty {
                    EmptyStateView(
                        title: "No planned sets yet",
                        message: "Add exercises you want to hit for this day.",
                        systemImage: "list.bullet.rectangle"
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.backgroundColor(for: colorScheme))
                    .marbleRowInsets()
                    .accessibilityIdentifier("SplitDayEditor.EmptyState")
                } else {
                    ForEach(orderedPlannedSets) { plannedSet in
                        Button {
                            openLog(for: plannedSet)
                        } label: {
                            PlannedSetRowView(plannedSet: plannedSet)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.backgroundColor(for: colorScheme))
                        .marbleRowInsets()
                        .accessibilityIdentifier(plannedSetIdentifier(plannedSet))
                        .swipeActions {
                            Button(role: .destructive) {
                                delete(plannedSet)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }

                Button {
                    showExercisePicker = true
                } label: {
                    Label("Add Planned Set", systemImage: "plus")
                        .font(MarbleTypography.rowSubtitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.backgroundColor(for: colorScheme))
                .marbleRowInsets()
                .accessibilityIdentifier("SplitDayEditor.AddPlannedSet")
            } header: {
                PlannedSetsHeaderView {
                    showExercisePicker = true
                }
            }

            Section {
                TextField("Workout name", text: $title)
                    .marbleFieldStyle()
                    .padding(.vertical, MarbleSpacing.s)
                    .accessibilityIdentifier("SplitDayEditor.Title")
            } header: {
                SectionHeaderView(title: "Workout")
            }

            Section {
                if showNotes || !notes.isEmpty {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .marbleFieldStyle()
                        .padding(.vertical, MarbleSpacing.s)
                        .accessibilityIdentifier("SplitDayEditor.Notes")
                } else {
                    Button("Add note") {
                        showNotes = true
                    }
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .padding(.vertical, MarbleSpacing.s)
                    .accessibilityIdentifier("SplitDayEditor.AddNote")
                }
            } header: {
                SectionHeaderView(title: "Notes")
            }

            Section {
                Button("Clear Day") {
                    clear()
                }
                .font(MarbleTypography.rowSubtitle)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .padding(.vertical, MarbleSpacing.s)
                .accessibilityIdentifier("SplitDayEditor.Clear")
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
        .accessibilityIdentifier("SplitDayEditor.List")
        .navigationTitle(day.weekday.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarGlassBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    save()
                }
                .accessibilityIdentifier("SplitDayEditor.Save")
            }
        }
        .onAppear {
            load()
        }
        .onChange(of: selectedExercise) { _, newValue in
            guard let newValue else { return }
            addPlannedSet(newValue)
            selectedExercise = nil
            showExercisePicker = false
        }
        .sheet(isPresented: $showExercisePicker) {
            NavigationStack {
                ExercisePickerView(selectedExercise: $selectedExercise)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .sheetGlassBackground()
        }
    }

    private func load() {
        title = day.title
        notes = day.notes ?? ""
        showNotes = !notes.isEmpty
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        day.title = trimmedTitle
        day.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        let now = AppEnvironment.now
        day.updatedAt = now
        day.plan?.updatedAt = now
        try? modelContext.save()
        dismiss()
    }

    private func clear() {
        title = ""
        notes = ""
        showNotes = false
        day.title = ""
        day.notes = nil
        day.plannedSets.forEach { modelContext.delete($0) }
        day.plannedSets = []
        let now = AppEnvironment.now
        day.updatedAt = now
        day.plan?.updatedAt = now
        try? modelContext.save()
    }

    private var orderedPlannedSets: [PlannedSet] {
        day.plannedSets.sorted {
            if $0.order != $1.order {
                return $0.order < $1.order
            }
            return $0.createdAt < $1.createdAt
        }
    }

    private func addPlannedSet(_ exercise: Exercise) {
        let nextOrder = (day.plannedSets.map { $0.order }.max() ?? -1) + 1
        let now = AppEnvironment.now
        let plannedSet = PlannedSet(order: nextOrder, notes: nil, createdAt: now, updatedAt: now, exercise: exercise, day: day)
        day.plannedSets.append(plannedSet)
        day.updatedAt = now
        day.plan?.updatedAt = now
        modelContext.insert(plannedSet)
        try? modelContext.save()
    }

    private func delete(_ plannedSet: PlannedSet) {
        if let index = day.plannedSets.firstIndex(where: { $0.id == plannedSet.id }) {
            day.plannedSets.remove(at: index)
        }
        modelContext.delete(plannedSet)
        let now = AppEnvironment.now
        day.updatedAt = now
        day.plan?.updatedAt = now
        try? modelContext.save()
    }

    private func openLog(for plannedSet: PlannedSet) {
        let targetDate = DateHelper.nextDate(for: day.weekday, from: AppEnvironment.now)
        quickLog.open(prefillDate: targetDate, prefillExerciseID: plannedSet.exercise.id)
    }

    private func plannedSetIdentifier(_ plannedSet: PlannedSet) -> String {
        let sanitized = plannedSet.exercise.name.replacingOccurrences(of: " ", with: "")
        return "SplitDayEditor.PlannedSet.\(sanitized)"
    }
}

private struct PlannedSetsHeaderView: View {
    let onAdd: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            Text("Planned Sets")
                .font(MarbleTypography.sectionTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            .accessibilityIdentifier("SplitDayEditor.AddPlannedSetHeader")
            .accessibilityLabel("Add planned set")
        }
        .padding(.vertical, MarbleSpacing.xs)
    }
}
