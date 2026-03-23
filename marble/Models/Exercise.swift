import Foundation
import SwiftData

@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var category: ExerciseCategory
    var customIconEmoji: String?
    var resistanceTrackingStyleRaw: String?
    var preferredDistanceUnitRaw: String?
    var metrics: ExerciseMetricsProfile
    var defaultRestSeconds: Int
    var isFavorite: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        category: ExerciseCategory,
        customIconEmoji: String? = nil,
        resistanceTrackingStyle: ResistanceTrackingStyle = .totalLoad,
        preferredDistanceUnit: DistanceUnit = .meters,
        metrics: ExerciseMetricsProfile,
        defaultRestSeconds: Int,
        isFavorite: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.customIconEmoji = nil
        self.resistanceTrackingStyleRaw = nil
        self.preferredDistanceUnitRaw = nil
        self.metrics = metrics
        self.defaultRestSeconds = defaultRestSeconds
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        setCustomIconEmoji(customIconEmoji)
        setResistanceTrackingStyle(resistanceTrackingStyle)
        setPreferredDistanceUnit(preferredDistanceUnit)
    }
}

extension Exercise {
    var resistanceTrackingStyle: ResistanceTrackingStyle {
        ResistanceTrackingStyle(rawValue: resistanceTrackingStyleRaw ?? "") ?? .totalLoad
    }

    var preferredDistanceUnit: DistanceUnit {
        DistanceUnit(rawValue: preferredDistanceUnitRaw ?? "") ?? .meters
    }

    func setCustomIconEmoji(_ emoji: String?) {
        customIconEmoji = emoji?.firstExerciseEmoji
    }

    func setResistanceTrackingStyle(_ style: ResistanceTrackingStyle) {
        resistanceTrackingStyleRaw = style == .totalLoad ? nil : style.rawValue
    }

    func setPreferredDistanceUnit(_ unit: DistanceUnit) {
        preferredDistanceUnitRaw = unit == .meters ? nil : unit.rawValue
    }

    var sanitizedCustomIconEmoji: String? {
        customIconEmoji?.firstExerciseEmoji
    }

    var displayIcon: ExerciseDisplayIcon {
        if let emoji = sanitizedCustomIconEmoji {
            return .emoji(emoji)
        }
        return .symbol(category.symbolName)
    }

    var weightInputTitle: String {
        resistanceTrackingStyle.fieldTitle
    }

    var weightInputHelperText: String {
        resistanceTrackingStyle.loggerHelperText
    }

    func storedWeight(from inputWeight: Double?) -> Double? {
        resistanceTrackingStyle.storedWeight(from: inputWeight)
    }

    func displayedWeightInput(from storedWeight: Double?) -> Double? {
        resistanceTrackingStyle.inputWeight(from: storedWeight)
    }

    func formattedWeightSummary(_ storedWeight: Double, unit: WeightUnit) -> String {
        let total = Formatters.weight.string(from: NSNumber(value: storedWeight)) ?? "\(storedWeight)"
        switch resistanceTrackingStyle {
        case .totalLoad:
            return "\(total) \(unit.symbol)"
        case .singleDumbbellPair:
            let single = displayedWeightInput(from: storedWeight) ?? storedWeight
            let formattedSingle = Formatters.weight.string(from: NSNumber(value: single)) ?? "\(single)"
            return "\(formattedSingle) \(unit.symbol) each (\(total) \(unit.symbol) total)"
        }
    }

    func formattedDistanceSummary(_ distance: Double, unit: DistanceUnit? = nil) -> String {
        let resolvedUnit = unit ?? preferredDistanceUnit
        let formattedDistance = Formatters.distance.string(from: NSNumber(value: distance)) ?? "\(distance)"
        return "\(formattedDistance) \(resolvedUnit.symbol)"
    }
}
