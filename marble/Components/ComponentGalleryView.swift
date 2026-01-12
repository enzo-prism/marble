import SwiftUI

#if DEBUG
struct ComponentGalleryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var segmentSelection = 0
    @State private var normalText = ""
    @State private var focusedText = "Focused"
    @State private var errorText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sectionTitle("Buttons")
                HStack(spacing: 12) {
                    Button("Primary") {}
                        .buttonStyle(.bordered)
                        .tint(Theme.primaryTextColor(for: colorScheme))
                        .accessibilityIdentifier("Gallery.PrimaryButton")
                    Button("Primary Disabled") {}
                        .buttonStyle(.bordered)
                        .tint(Theme.primaryTextColor(for: colorScheme))
                        .disabled(true)
                        .accessibilityIdentifier("Gallery.PrimaryButton.Disabled")
                }

                sectionTitle("Glass Nav")
                HStack(spacing: 12) {
                    navButton(systemName: "chevron.left", identifier: "Gallery.NavButton.Back")
                    navButton(systemName: "ellipsis", identifier: "Gallery.NavButton.More")
                }

                sectionTitle("Chips")
                HStack(spacing: 8) {
                    chip(text: "Selected", isSelected: true, isDisabled: false, identifier: "Gallery.Chip.Selected")
                    chip(text: "Default", isSelected: false, isDisabled: false, identifier: "Gallery.Chip.Default")
                    chip(text: "Disabled", isSelected: false, isDisabled: true, identifier: "Gallery.Chip.Disabled")
                }

                sectionTitle("Form Fields")
                fieldRow(title: "Normal", text: $normalText, style: .normal)
                fieldRow(title: "Focused", text: $focusedText, style: .focused)
                fieldRow(title: "Error", text: $errorText, style: .error)

                sectionTitle("Segments")
                Picker("Segments", selection: $segmentSelection) {
                    Text("One").tag(0)
                    Text("Two").tag(1)
                    Text("Three").tag(2)
                }
                .pickerStyle(.segmented)
                .tint(Theme.dividerColor(for: colorScheme))
                .accessibilityIdentifier("Gallery.Segments")
            }
            .padding(16)
        }
        .background(Theme.backgroundColor(for: colorScheme))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
    }

    private func navButton(systemName: String, identifier: String) -> some View {
        Button {} label: {
            Image(systemName: systemName)
                .font(.headline)
                .frame(width: 36, height: 36)
        }
        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
        .background(GlassPillBackground())
        .accessibilityIdentifier(identifier)
    }

    private func chip(text: String, isSelected: Bool, isDisabled: Bool, identifier: String) -> some View {
        Text(text)
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Theme.dividerColor(for: colorScheme) : Theme.chipFillColor(for: colorScheme))
            )
            .opacity(isDisabled ? 0.5 : 1.0)
            .accessibilityIdentifier(identifier)
    }

    private enum FieldStyle {
        case normal
        case focused
        case error
    }

    private func fieldRow(title: String, text: Binding<String>, style: FieldStyle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            TextField(title, text: text)
                .textFieldStyle(.plain)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(borderColor(for: style), lineWidth: style == .focused ? 2 : 1)
                )
        }
    }

    private func borderColor(for style: FieldStyle) -> Color {
        switch style {
        case .normal:
            return Theme.dividerColor(for: colorScheme)
        case .focused:
            return Theme.primaryTextColor(for: colorScheme)
        case .error:
            return Theme.secondaryTextColor(for: colorScheme)
        }
    }
}
#endif
