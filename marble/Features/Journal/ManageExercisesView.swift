import SwiftUI
import SwiftData

struct ManageExercisesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \Exercise.name)
    private var exercises: [Exercise]

    @Query(sort: \SetEntry.performedAt, order: .reverse)
    private var entries: [SetEntry]

    @State private var showingNewExercise = false
    @State private var showCannotDelete = false
    @State private var cannotDeleteName = ""

    var body: some View {
        List {
            ForEach(exercises) { exercise in
                NavigationLink {
                    ExerciseEditorView(exercise: exercise)
                } label: {
                    HStack {
                        Image(systemName: exercise.category.symbolName)
                            .frame(width: 24)
                        Text(exercise.name)
                    }
                }
                .accessibilityIdentifier("ManageExercises.Row.\(exercise.id.uuidString)")
            }
            .onDelete(perform: deleteExercises)
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
        .accessibilityIdentifier("ManageExercises.List")
        .navigationTitle("Manage Exercises")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarGlassBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewExercise = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("ManageExercises.Add")
            }
        }
        .sheet(isPresented: $showingNewExercise) {
            NavigationStack {
                ExerciseEditorView(exercise: nil)
            }
        }
        .alert("Cannot Delete Exercise", isPresented: $showCannotDelete) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\"\(cannotDeleteName)\" has logged sets. Remove those sets before deleting.")
        }
    }

    private func deleteExercises(at offsets: IndexSet) {
        for index in offsets {
            let exercise = exercises[index]
            let count = entries.filter { $0.exercise.id == exercise.id }.count
            if count > 0 {
                cannotDeleteName = exercise.name
                showCannotDelete = true
                continue
            }
            modelContext.delete(exercise)
        }
    }
}
