import Foundation

enum AppTab: Hashable {
    case journal
    case calendar
    case split
    case supplements
    case trends
}

@Observable
final class TabSelection {
    var selected: AppTab = .journal
}
