import SwiftUI
import SwiftData

struct SupplementTypeEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let type: SupplementType?

    @State private var name: String = ""
    @State private var defaultDose: Double?
    @State private var unit: SupplementUnit = .g
    @State private var isFavorite: Bool = false

    var body: some View {
        List {
            Section {
                TextField("Name", text: $name)
                    .marbleFieldStyle()
                    .accessibilityIdentifier("SupplementTypeEditor.Name")
                OptionalNumberField(title: "Default Dose", formatter: Formatters.dose, value: $defaultDose, accessibilityIdentifier: "SupplementTypeEditor.DefaultDose")
                Picker("Unit", selection: $unit) {
                    ForEach(SupplementUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .accessibilityIdentifier("SupplementTypeEditor.Unit")
                Toggle("Favorite", isOn: $isFavorite)
                    .tint(Theme.dividerColor(for: colorScheme))
                    .accessibilityIdentifier("SupplementTypeEditor.Favorite")
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
        .navigationTitle(type == nil ? "New Type" : "Edit Type")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarGlassBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    save()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("SupplementTypeEditor.Save")
            }
        }
        .onAppear {
            if let type {
                load(from: type)
            }
        }
    }

    private func load(from type: SupplementType) {
        name = type.name
        defaultDose = type.defaultDose
        unit = type.unit
        isFavorite = type.isFavorite
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let type {
            type.name = trimmedName
            type.defaultDose = defaultDose
            type.unit = unit
            type.isFavorite = isFavorite
        } else {
            let newType = SupplementType(name: trimmedName, defaultDose: defaultDose, unit: unit, isFavorite: isFavorite)
            modelContext.insert(newType)
        }
        dismiss()
    }
}
