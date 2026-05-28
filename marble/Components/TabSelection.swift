import Combine
import Foundation

enum AppTab: Hashable {
    case journal
    case calendar
    case empire
    case supplements
    case trends
}

final class TabSelection: ObservableObject {
    @Published var selected: AppTab = .journal
}
