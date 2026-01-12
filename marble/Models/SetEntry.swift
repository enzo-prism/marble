import Foundation
import SwiftData

@Model
final class SetEntry {
    @Attribute(.unique) var id: UUID
    var exercise: Exercise
    var performedAt: Date
    var weight: Double?
    var weightUnit: WeightUnit
    var reps: Int?
    var durationSeconds: Int?
    var difficulty: Int
    var restAfterSeconds: Int
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        exercise: Exercise,
        performedAt: Date,
        weight: Double? = nil,
        weightUnit: WeightUnit = .lb,
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        difficulty: Int = 8,
        restAfterSeconds: Int,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.exercise = exercise
        self.performedAt = performedAt
        self.weight = weight
        self.weightUnit = weightUnit
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.difficulty = difficulty
        self.restAfterSeconds = restAfterSeconds
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

