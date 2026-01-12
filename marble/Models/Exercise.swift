import Foundation
import SwiftData

@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var category: ExerciseCategory
    var metrics: ExerciseMetricsProfile
    var defaultRestSeconds: Int
    var isFavorite: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        category: ExerciseCategory,
        metrics: ExerciseMetricsProfile,
        defaultRestSeconds: Int,
        isFavorite: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.metrics = metrics
        self.defaultRestSeconds = defaultRestSeconds
        self.isFavorite = isFavorite
        self.createdAt = createdAt
    }
}
