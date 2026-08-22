import SwiftUI

/// Switches Journal / Calendar / Supplements inside the Log tab. The standard
/// layout stays segmented, while accessibility text sizes use full-width rows
/// so the labels never compete for horizontal space. Identifiers stay on the
/// controls (never the container) so tests can still find `Tab.Calendar` and
/// `Tab.Supplements` after those destinations left the tab bar.
struct LogModePicker: View {
    @Environment(TabSelection.self) private var tabSelection
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        @Bindable var tabs = tabSelection
        let selection = Binding(
            get: { tabs.selected.isLogSection ? tabs.selected : tabs.lastLogTab },
            set: { tabs.selectLogMode($0) }
        )

        if dynamicTypeSize.isAccessibilitySize {
            accessibilityPicker(selection: selection)
        } else {
            segmentedPicker(selection: selection)
        }
    }

    private func segmentedPicker(selection: Binding<AppTab>) -> some View {
        Picker("Log", selection: selection) {
            Text("Sets")
                .tag(AppTab.journal)
                .accessibilityIdentifier("Log.Mode.Sets")
            Text("Calendar")
                .tag(AppTab.calendar)
                .accessibilityIdentifier("Tab.Calendar")
            Text("Supplements")
                .tag(AppTab.supplements)
                .accessibilityIdentifier("Tab.Supplements")
        }
        .pickerStyle(.segmented)
        .tint(Theme.primaryTextColor(for: colorScheme))
        .accessibilityLabel("Log section")
    }

    private func accessibilityPicker(selection: Binding<AppTab>) -> some View {
        VStack(spacing: MarbleSpacing.xxs) {
            accessibilityModeButton(
                title: "Sets",
                identifier: "Log.Mode.Sets",
                tab: .journal,
                selection: selection
            )
            accessibilityModeButton(
                title: "Calendar",
                identifier: "Tab.Calendar",
                tab: .calendar,
                selection: selection
            )
            accessibilityModeButton(
                title: "Supplements",
                identifier: "Tab.Supplements",
                tab: .supplements,
                selection: selection
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Log section")
    }

    private func accessibilityModeButton(
        title: String,
        identifier: String,
        tab: AppTab,
        selection: Binding<AppTab>
    ) -> some View {
        let isSelected = selection.wrappedValue == tab

        return Button {
            selection.wrappedValue = tab
        } label: {
            HStack(spacing: MarbleSpacing.s) {
                Text(title)
                    .font(MarbleTypography.rowTitle)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: MarbleSpacing.s)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, MarbleSpacing.s)
            .padding(.vertical, MarbleSpacing.xs)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            .background(
                RoundedRectangle(cornerRadius: MarbleCornerRadius.small, style: .continuous)
                    .fill(isSelected
                        ? Theme.chipFillColor(for: colorScheme)
                        : Theme.surfaceColor(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MarbleCornerRadius.small, style: .continuous)
                    .stroke(
                        isSelected
                            ? Theme.dividerColor(for: colorScheme)
                            : Theme.subtleDividerColor(for: colorScheme),
                        lineWidth: isSelected ? 1 : 0.75
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: MarbleCornerRadius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
