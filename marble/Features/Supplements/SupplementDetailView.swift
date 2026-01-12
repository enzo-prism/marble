import SwiftUI
import SwiftData

struct SupplementDetailView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \SupplementType.name)
    private var types: [SupplementType]

    @Bindable var entry: SupplementEntry

    var body: some View {
        List {
            Section {
                Picker("Type", selection: $entry.type) {
                    ForEach(types) { type in
                        Text(type.name).tag(type)
                    }
                }
                .accessibilityIdentifier("SupplementDetail.Type")

                OptionalNumberField(title: "Dose", formatter: Formatters.dose, value: doseBinding, accessibilityIdentifier: "SupplementDetail.Dose")

                Picker("Unit", selection: $entry.unit) {
                    ForEach(SupplementUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .accessibilityIdentifier("SupplementDetail.Unit")

                DatePicker("Taken", selection: $entry.takenAt)
                    .accessibilityIdentifier("SupplementDetail.TakenAt")
            }

            Section {
                TextField("Notes", text: notesBinding, axis: .vertical)
                    .accessibilityIdentifier("SupplementDetail.Notes")
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
        .navigationTitle("Supplement")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarGlassBackground()
        .onDisappear {
            entry.updatedAt = AppEnvironment.now
        }
    }

    private var doseBinding: Binding<Double?> {
        Binding(
            get: { entry.dose },
            set: { entry.dose = $0 }
        )
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { entry.notes ?? "" },
            set: { entry.notes = $0.isEmpty ? nil : $0 }
        )
    }
}
