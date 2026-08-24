import SwiftUI

/// Switches Journal / Calendar / Supplements inside the Log tab. The standard
/// layout stays segmented, while accessibility text sizes use a compact menu
/// so navigation doesn't consume most of the screen. Identifiers stay on the
/// controls (never the container) so UI automation can select every mode.
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
        Menu {
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
        } label: {
            HStack(spacing: MarbleSpacing.s) {
                Text(accessibilityTitle(for: selection.wrappedValue))
                    .font(MarbleTypography.rowTitle)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: MarbleSpacing.s)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.body.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, MarbleSpacing.s)
            .padding(.vertical, MarbleSpacing.xs)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            .background(
                RoundedRectangle(cornerRadius: MarbleCornerRadius.small, style: .continuous)
                    .fill(Theme.chipFillColor(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MarbleCornerRadius.small, style: .continuous)
                    .stroke(Theme.dividerColor(for: colorScheme), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: MarbleCornerRadius.small, style: .continuous))
        }
        .accessibilityLabel("Log section, \(accessibilityTitle(for: selection.wrappedValue))")
        .accessibilityHint("Shows Sets, Calendar, and Supplements.")
        .accessibilityIdentifier("Log.Mode.Menu")
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
            Label(title, systemImage: isSelected ? "checkmark" : "circle")
        }
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func accessibilityTitle(for tab: AppTab) -> String {
        switch tab {
        case .journal: "Sets"
        case .calendar: "Calendar"
        case .supplements: "Supplements"
        default: "Sets"
        }
    }
}
