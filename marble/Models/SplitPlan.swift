import Foundation
import SwiftData

@Model
final class SplitPlan {
    @Attribute(.unique) var id: UUID
    var name: String
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade) var days: [SplitDay]

    init(
        id: UUID = UUID(),
        name: String,
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        days: [SplitDay] = []
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.days = days
    }
}

@Model
final class SplitDay {
    @Attribute(.unique) var id: UUID
    var weekday: Weekday
    var title: String
    var notes: String?
    var order: Int
    var createdAt: Date
    var updatedAt: Date
    @Relationship(inverse: \SplitPlan.days) var plan: SplitPlan?

    init(
        id: UUID = UUID(),
        weekday: Weekday,
        title: String = "",
        notes: String? = nil,
        order: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        plan: SplitPlan? = nil
    ) {
        self.id = id
        self.weekday = weekday
        self.title = title
        self.notes = notes
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.plan = plan
    }
}
