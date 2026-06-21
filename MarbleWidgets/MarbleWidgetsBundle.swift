import SwiftUI
import WidgetKit

// Entry point for the MarbleWidgets widget-extension target. Add more widgets (Home Screen,
// Lock Screen, Control) to `body` over time; today it hosts the rest-timer Live Activity.
@main
struct MarbleWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RestTimerLiveActivity()
    }
}
