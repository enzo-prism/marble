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
    @State private var iconSource: SupplementIconSource = .standard
    @State private var customIconEmoji: String = ""

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
                    .tint(Theme.toggleOnColor)
                    .accessibilityIdentifier("SupplementTypeEditor.Favorite")
            }

            iconSection
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
        .navigationTitle(type == nil ? "New Type" : "Edit Type")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarGlassBackground()
        .marbleKeyboardToolbar(
            primaryAction: KeyboardToolbarAction(
                title: "Save",
                accessibilityIdentifier: "Keyboard.Save",
                isEnabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                handler: save
            )
        )
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
        .onChange(of: customIconEmoji) { _, newValue in
            let sanitized = newValue.firstEmoji ?? ""
            if sanitized != newValue {
                customIconEmoji = sanitized
            }
        }
        .onChange(of: iconSource) { _, _ in
            ensureDefaultEmojiSelection()
        }
    }

    private var iconSection: some View {
        Section {
            LabeledContent {
                SupplementIconView(icon: draftDisplayIcon, fontSize: 26, frameSize: 36)
                    .accessibilityHidden(true)
            } label: {
                Text(iconSource == .emoji ? "Custom emoji" : "Default icon")
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            }

            Picker("Icon style", selection: $iconSource) {
                ForEach(SupplementIconSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("SupplementTypeEditor.IconMode")

            if iconSource == .emoji {
                TextField("Emoji", text: $customIconEmoji)
                    .marbleFieldStyle()
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("SupplementTypeEditor.CustomEmoji")

                emojiSuggestionRow
            }
        } header: {
            SectionHeaderView(title: "Icon")
        } footer: {
            Text(iconFooter)
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        }
        .textCase(nil)
        .listRowBackground(Theme.backgroundColor(for: colorScheme))
    }

    private var emojiSuggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MarbleSpacing.xs) {
                ForEach(Array(SupplementIcon.emojiSuggestions.enumerated()), id: \.offset) { index, emoji in
                    Button {
                        selectSuggestedEmoji(emoji)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 24))
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                                    .fill(Theme.surfaceColor(for: colorScheme))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                                    .strokeBorder(
                                        resolvedCustomIconEmoji == emoji
                                            ? Theme.primaryTextColor(for: colorScheme)
                                            : Theme.subtleDividerColor(for: colorScheme),
                                        lineWidth: resolvedCustomIconEmoji == emoji ? 2 : 0.75
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("SupplementTypeEditor.EmojiSuggestion.\(index)")
                    .accessibilityLabel("Emoji option \(index + 1)")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var resolvedCustomIconEmoji: String? {
        customIconEmoji.firstEmoji
    }

    private var draftDisplayIcon: SupplementDisplayIcon {
        if iconSource == .emoji, let emoji = resolvedCustomIconEmoji {
            return .emoji(emoji)
        }
        return .symbol(SupplementIcon.defaultSymbolName)
    }

    private var iconFooter: String {
        if iconSource == .emoji {
            return resolvedCustomIconEmoji == nil
                ? "Choose one emoji. If you paste several, Marble keeps the first valid one."
                : "Your emoji appears everywhere this supplement is shown."
        }
        return "Uses the default pill icon until you switch to a custom emoji."
    }

    private func selectSuggestedEmoji(_ emoji: String) {
        customIconEmoji = emoji
    }

    private func ensureDefaultEmojiSelection() {
        guard iconSource == .emoji, resolvedCustomIconEmoji == nil else { return }
        customIconEmoji = SupplementIcon.emojiSuggestions.first ?? ""
    }

    private func load(from type: SupplementType) {
        name = type.name
        defaultDose = type.defaultDose
        unit = type.unit
        isFavorite = type.isFavorite
        customIconEmoji = type.sanitizedCustomIconEmoji ?? ""
        iconSource = type.sanitizedCustomIconEmoji == nil ? .standard : .emoji
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEmoji = iconSource == .emoji ? resolvedCustomIconEmoji : nil
        if let type {
            type.name = trimmedName
            type.defaultDose = defaultDose
            type.unit = unit
            type.isFavorite = isFavorite
            type.setCustomIconEmoji(resolvedEmoji)
        } else {
            let newType = SupplementType(
                name: trimmedName,
                defaultDose: defaultDose,
                unit: unit,
                isFavorite: isFavorite,
                customIconEmoji: resolvedEmoji
            )
            modelContext.insert(newType)
        }
        dismiss()
    }
}
