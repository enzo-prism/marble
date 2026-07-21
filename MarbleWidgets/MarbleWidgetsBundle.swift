import SwiftUI
import WidgetKit

// Entry point for the MarbleWidgets widget-extension target: the rest-timer Live Activity,
// the Home/Lock Screen weekly-goal widget, and the Control Center quick-log control.
@main
struct MarbleWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RestTimerLiveActivity()
        WeeklyGoalWidget()
        QuickLogControl()
    }
}
