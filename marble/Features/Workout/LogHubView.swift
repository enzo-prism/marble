import SwiftUI

/// Log tab: one history surface with Sets / Calendar / Supplements as modes.
struct LogHubView: View {
    @Environment(TabSelection.self) private var tabSelection

    var body: some View {
        switch tabSelection.selected {
        case .calendar:
            CalendarView()
        case .supplements:
            SupplementsView()
        default:
            JournalView()
        }
    }
}
