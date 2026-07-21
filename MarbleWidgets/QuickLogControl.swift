import AppIntents
import SwiftUI
import WidgetKit

// NOTE: This file belongs to the **MarbleWidgets widget-extension target**, not the app.
//
// A `ControlWidget` makes "Log a set" assignable to Control Center, the Lock Screen controls,
// and the Action button. The extension can only reference intent types it compiles itself,
// which is why the action is `OpenQuickLogControlIntent` from the dual-target
// `marble/Shared/MarbleSharedIntents.swift` rather than the app-only `OpenQuickLogIntent`.
//
// Registration in `MarbleWidgetsBundle` is owned by the integrator.

struct QuickLogControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "QuickLogControl") {
            ControlWidgetButton(action: OpenQuickLogControlIntent()) {
                Label("Log a Set", systemImage: "plus.circle")
            }
        }
        .displayName("Log a Set")
        .description("Opens Marble straight to the set logger.")
    }
}
