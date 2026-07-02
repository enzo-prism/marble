import Foundation
import SwiftData

@Model
final class SetEntry {
    #Index<SetEntry>([\.performedAt])

    @Attribute(.unique) var id: UUID
    var exercise: Exercise
    var performedAt: Date
    var weight: Double?
    var weightUnit: WeightUnit
    var reps: Int?
    var distance: Double?
    var distanceUnitRaw: String?
    var durationSeconds: Int?
    var difficulty: Int
    var restAfterSeconds: Int
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    /// The imported workout this entry came from, when it was created by the
    /// import pipeline rather than logged by hand. Optional and additive; the
    /// inverse lives on `ImportedWorkout.entries`. Duplicating a set does NOT
    /// carry this over — a manual duplicate is the user's own log.
    var importedWorkout: ImportedWorkout?

    init(
        id: UUID = UUID(),
        exercise: Exercise,
        performedAt: Date,
        weight: Double? = nil,
        weightUnit: WeightUnit = .lb,
        reps: Int? = nil,
        distance: Double? = nil,
        distanceUnit: DistanceUnit = .meters,
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
        self.distance = distance
        self.distanceUnitRaw = nil
        self.durationSeconds = durationSeconds
        self.difficulty = difficulty
        self.restAfterSeconds = restAfterSeconds
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.distanceUnit = distanceUnit
    }
}

extension SetEntry {
    var distanceUnit: DistanceUnit {
        get { DistanceUnit(rawValue: distanceUnitRaw ?? "") ?? .meters }
        set { distanceUnitRaw = newValue == .meters ? nil : newValue.rawValue }
    }

    func duplicated(at date: Date) -> SetEntry {
        SetEntry(
            exercise: exercise,
            performedAt: date,
            weight: weight,
            weightUnit: weightUnit,
            reps: reps,
            distance: distance,
            distanceUnit: distanceUnit,
            durationSeconds: durationSeconds,
            difficulty: difficulty,
            restAfterSeconds: restAfterSeconds,
            notes: notes,
            createdAt: date,
            updatedAt: date
        )
    }
}
