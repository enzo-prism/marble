import Foundation
import SwiftUI

enum AppTab: Hashable {
    case addWorkout
    case journal
    case calendar
    case supplements
    case trends

    /// The three items that actually sit in the tab bar.
    var tabBarItem: AppTab {
        switch self {
        case .calendar, .supplements:
            return .journal
        case .addWorkout, .journal, .trends:
            return self
        }
    }

    var isLogSection: Bool {
        switch self {
        case .journal, .calendar, .supplements:
            return true
        case .addWorkout, .trends:
            return false
        }
    }
}

@Observable
final class TabSelection {
    /// Logical destination, including Log subsections (calendar / supplements)
    /// that share the Log tab.
    var selected: AppTab = .addWorkout

    /// Last Log subsection, restored when returning to the Log tab.
    var lastLogTab: AppTab = .journal

    var tabBarSelection: AppTab {
        get { selected.tabBarItem }
        set {
            if newValue == .journal {
                selected = selected.isLogSection ? selected : lastLogTab
            } else {
                selected = newValue
            }
        }
    }

    func selectLogMode(_ tab: AppTab) {
        guard tab.isLogSection else { return }
        selected = tab
        lastLogTab = tab
    }
}

private struct LogSetZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var logSetZoomNamespace: Namespace.ID? {
        get { self[LogSetZoomNamespaceKey.self] }
        set { self[LogSetZoomNamespaceKey.self] = newValue }
    }
}
