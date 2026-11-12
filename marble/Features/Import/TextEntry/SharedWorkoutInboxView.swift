import SwiftUI

struct SharedWorkoutInboxView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [SharedWorkoutInbox.Item] = []
    @State private var selected: SharedWorkoutInbox.Item?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.secondary) }
                if items.isEmpty {
                    ContentUnavailableView("No shared workouts", systemImage: "tray", description: Text("Share text or a text/CSV file to Marble from Notes or Files. Review it here before adding it to your journal."))
                }
                ForEach(items) { item in
                    Button { selected = item } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.text).lineLimit(3).foregroundStyle(.primary)
                            Text(item.createdAt, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("SharedWorkout.Review.\(item.id)")
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            do { try SharedWorkoutInbox.remove(id: item.id); reload() }
                            catch { self.error = error.localizedDescription }
                        }.accessibilityIdentifier("SharedWorkout.Delete.\(item.id)")
                    }
                }
            }
            .navigationTitle("Shared Workouts")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("SharedWorkout.Done")
                }
            }
            .task { reload() }
            .sheet(item: $selected, onDismiss: reload) { item in SharedWorkoutReview(item: item) }
        }
    }
    private func reload() {
        do { items = try SharedWorkoutInbox.items(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

private struct SharedWorkoutReview: View {
    let item: SharedWorkoutInbox.Item
    @State private var model: WorkoutTextEntryViewModel
    init(item: SharedWorkoutInbox.Item) {
        self.item = item
        _model = State(initialValue: WorkoutTextEntryViewModel(initialText: item.text,
            draftStore: WorkoutEntryDraftStore.applicationStore(slot: "shared-\(item.id)")))
    }
    var body: some View {
        WorkoutTextEntryView(viewModel: model)
            .onChange(of: model.phase) { _, phase in
                // A queue item survives dismissals, parsing failures and app termination.
                // It is consumed only after the existing importer confirms persistence.
                if phase == .imported { try? SharedWorkoutInbox.remove(id: item.id) }
            }
    }
}
