import SwiftUI
import SwiftData

struct SupplementTypeManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \SupplementType.name)
    private var types: [SupplementType]

    @Query(sort: \SupplementEntry.takenAt, order: .reverse)
    private var entries: [SupplementEntry]

    @State private var showingNewType = false
    @State private var showCannotDelete = false
    @State private var cannotDeleteName = ""

    var body: some View {
        List {
            ForEach(types) { type in
                NavigationLink {
                    SupplementTypeEditorView(type: type)
                } label: {
                    Text(type.name)
                }
                .accessibilityIdentifier("SupplementType.Row.\(type.id.uuidString)")
            }
            .onDelete(perform: deleteTypes)
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
        .accessibilityIdentifier("SupplementType.List")
        .navigationTitle("Supplement Types")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarGlassBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewType = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("SupplementType.Add")
            }
        }
        .sheet(isPresented: $showingNewType) {
            NavigationStack {
                SupplementTypeEditorView(type: nil)
            }
        }
        .alert("Cannot Delete Type", isPresented: $showCannotDelete) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\"\(cannotDeleteName)\" has logged entries. Remove those entries before deleting.")
        }
    }

    private func deleteTypes(at offsets: IndexSet) {
        for index in offsets {
            let type = types[index]
            let count = entries.filter { $0.type.id == type.id }.count
            if count > 0 {
                cannotDeleteName = type.name
                showCannotDelete = true
                continue
            }
            modelContext.delete(type)
        }
    }
}
