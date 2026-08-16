import SwiftUI

/// Segmented control that switches Journal / Calendar / Supplements inside the
/// Log tab. Identifiers stay on the segments (never the picker) so tests can
/// still find `Tab.Calendar` and `Tab.Supplements` after those destinations
/// left the tab bar.
struct LogModePicker: View {
    @Environment(TabSelection.self) private var tabSelection
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        @Bindable var tabs = tabSelection
        Picker("Log", selection: Binding(
            get: { tabs.selected.isLogSection ? tabs.selected : tabs.lastLogTab },
            set: { tabs.selectLogMode($0) }
        )) {
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
}
