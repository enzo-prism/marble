import SwiftUI
import SwiftData

struct SplitDayEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    let day: SplitDay

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var showNotes = false

    var body: some View {
        List {
            Section {
                TextField("Workout name", text: $title)
                    .marbleFieldStyle()
                    .accessibilityIdentifier("SplitDayEditor.Title")
            } header: {
                SectionHeaderView(title: "Workout")
            }

            Section {
                if showNotes || !notes.isEmpty {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .marbleFieldStyle()
                        .accessibilityIdentifier("SplitDayEditor.Notes")
                } else {
                    Button("Add note") {
                        showNotes = true
                    }
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
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
    }
}
