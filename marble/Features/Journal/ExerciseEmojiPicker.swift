import SwiftUI

struct ExerciseEmojiPicker: View {
    @Binding var draft: ExerciseEditorDraft
    @Environment(\.colorScheme) private var colorScheme
    @State private var refinement: (name: String, icons: [String])?

    var body: some View {
        let name = draft.trimmedName
        let selected = draft.iconSource == .emoji ? draft.resolvedCustomIconEmoji : nil
        let matched = ExerciseEmojiSuggestions.matchedIcons(for: name)
        let refined = refinement?.name == name ? refinement?.icons : nil
        let choices = ExerciseEmojiSuggestions.choices(name: name, selected: selected,
            candidates: matched ?? refined ?? [], fallback: draft.category.emojiSuggestions)

        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Text("Suggested icons")
                .font(MarbleTypography.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            HStack(spacing: MarbleSpacing.s) {
                ForEach(choices, id: \.self) { icon in
                    let isSelected = selected == icon
                    Button {
                        draft.iconSource = isSelected ? .category : .emoji
                        draft.customIconEmoji = isSelected ? "" : icon
                        MarbleHaptics.selection()
                    } label: {
                        Text(icon)
                            .font(.title2)
                            .frame(minWidth: 46, minHeight: 44)
                            .background(Theme.chipFillColor(for: colorScheme), in: .rect(cornerRadius: MarbleCornerRadius.medium))
                            .overlay {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: MarbleCornerRadius.medium)
                                        .strokeBorder(Theme.primaryTextColor(for: colorScheme), lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Use \(icon) icon")
                    .accessibilityHint(isSelected ? "Tap again to use the category icon." : "Selects this exercise icon.")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("ExerciseEditor.SuggestedIcon.\(icon)")
                }
            }
        }
        .task(id: name) {
            guard matched == nil, selected == nil, name.firstExerciseEmoji == nil, name.count >= 3,
                  !TestHooks.isUITesting else { return }
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            guard !Task.isCancelled, draft.iconSource == .category,
                  let icons = await ExerciseEmojiSuggestions.modelIcons(for: name),
                  !Task.isCancelled, draft.trimmedName == name, draft.iconSource == .category else { return }
            refinement = (name, icons)
        }
    }
}
