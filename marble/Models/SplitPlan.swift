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
    @Relationship(deleteRule: .cascade) var plannedSets: [PlannedSet]

    init(
        id: UUID = UUID(),
        weekday: Weekday,
        title: String = "",
        notes: String? = nil,
        order: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        plan: SplitPlan? = nil,
        plannedSets: [PlannedSet] = []
    ) {
        self.id = id
        self.weekday = weekday
        self.title = title
        self.notes = notes
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.plan = plan
        self.plannedSets = plannedSets
    }
}

@Model
final class PlannedSet {
    @Attribute(.unique) var id: UUID
    var order: Int
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var exercise: Exercise
    @Relationship(inverse: \SplitDay.plannedSets) var day: SplitDay?

    init(
        id: UUID = UUID(),
        order: Int = 0,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        exercise: Exercise,
        day: SplitDay? = nil
    ) {
        self.id = id
        self.order = order
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.exercise = exercise
        self.day = day
    }
}
