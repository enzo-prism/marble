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
                        .buttonStyle(MarbleActionButtonStyle())
                        .accessibilityIdentifier("Gallery.PrimaryButton")
                    Button("Primary Disabled") {}
                        .buttonStyle(MarbleActionButtonStyle())
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
                    MarbleChipLabel(title: "Selected", isSelected: true, isDisabled: false, isExpanded: false)
                        .accessibilityIdentifier("Gallery.Chip.Selected")
                    MarbleChipLabel(title: "Default", isSelected: false, isDisabled: false, isExpanded: false)
                        .accessibilityIdentifier("Gallery.Chip.Default")
                    MarbleChipLabel(title: "Disabled", isSelected: false, isDisabled: true, isExpanded: false)
                        .accessibilityIdentifier("Gallery.Chip.Disabled")
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
            .font(MarbleTypography.sectionTitle)
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

    private enum FieldStyle {
        case normal
        case focused
        case error
    }

    private func fieldRow(title: String, text: Binding<String>, style: FieldStyle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(MarbleTypography.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            TextField(title, text: text)
                .marbleFieldStyle(fieldState(for: style))
        }
    }

    private func fieldState(for style: FieldStyle) -> MarbleFieldState {
        switch style {
        case .normal:
            return .normal
        case .focused:
            return .focused
        case .error:
            return .error
        }
    }
}
#endif
