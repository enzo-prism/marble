import Foundation
import UIKit

enum ExerciseCategory: String, Codable, CaseIterable, Identifiable {
    case chest
    case back
    case shoulders
    case biceps
    case triceps
    case core
    case quads
    case hamstrings
    case calves
    case legs
    case power
    case bar
    case recover
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest:
            return "Chest"
        case .back:
            return "Back"
        case .shoulders:
            return "Shoulders"
        case .biceps:
            return "Biceps"
        case .triceps:
            return "Triceps"
        case .core:
            return "Core"
        case .quads:
            return "Quads"
        case .hamstrings:
            return "Hamstrings"
        case .calves:
            return "Calves"
        case .legs:
            return "Legs"
        case .power:
            return "Power"
        case .bar:
            return "Bar"
        case .recover:
            return "Recover"
        case .other:
            return "Other"
        }
    }

    var symbolName: String {
        ExerciseSystemSymbolResolver.resolvedName(
            preferredSymbolName,
            fallback: fallbackSymbolName
        )
    }

    private var preferredSymbolName: String {
        switch self {
        case .chest:
            return "heart.fill"
        case .back:
            return "arrow.triangle.2.circlepath"
        case .shoulders:
            return "figure.strengthtraining.traditional"
        case .biceps:
            return "dumbbell.fill"
        case .triceps:
            return "dumbbell"
        case .core:
            return "circle.grid.cross"
        case .quads:
            return "figure.run"
        case .hamstrings:
            return "figure.walk.motion"
        case .calves:
            return "figure.stairs"
        case .legs:
            return "figure.walk"
        case .power:
            return "bolt.fill"
        case .bar:
            return "figure.gymnastics"
        case .recover:
            if #available(iOS 18.0, *) {
                return "sauna"
            }
            return "flame.fill"
        case .other:
            return "circle.dashed"
        }
    }

    private var fallbackSymbolName: String {
        switch self {
        case .recover:
            return "flame.fill"
        default:
            return "circle.dashed"
        }
    }

    var emojiSuggestions: [String] {
        switch self {
        case .chest:
            return ["🏋️", "💪", "🔥", "🫀", "🦾", "⚡️"]
        case .back:
            return ["🪽", "💪", "🦍", "⚡️", "🏔️", "🦾"]
        case .shoulders:
            return ["💪", "🦾", "⚡️", "🏋️", "🔥", "🎯"]
        case .biceps:
            return ["💪", "🦾", "🔥", "⚡️", "🏋️", "🦍"]
        case .triceps:
            return ["💪", "🦾", "⚡️", "🔥", "🏋️", "🎯"]
        case .core:
            return ["🧱", "🔥", "⚡️", "🌀", "🫁", "🎯"]
        case .quads:
            return ["🦵", "🔥", "🏃", "⚡️", "🧗", "🎯"]
        case .hamstrings:
            return ["🦵", "🏃", "🔥", "⚡️", "🧗", "🎯"]
        case .calves:
            return ["🦵", "⚡️", "🔥", "🏃", "🧗", "🎯"]
        case .legs:
            return ["🦵", "🏃", "🔥", "⚡️", "🧗", "🏋️"]
        case .power:
            return ["⚡️", "🚀", "🔥", "🏋️", "💥", "🦍"]
        case .bar:
            return ["🧗", "🦍", "💪", "⚡️", "🔥", "🎯"]
        case .recover:
            return ["🧘", "🫧", "🧖", "🌿", "😌", "☀️"]
        case .other:
            return ["⭐️", "🎯", "⚡️", "🔥", "💪", "🧩"]
        }
    }
}

private enum ExerciseSystemSymbolResolver {
    private static let universalFallback = "circle.dashed"

    static func resolvedName(_ preferred: String, fallback: String) -> String {
        if UIImage(systemName: preferred) != nil {
            return preferred
        }

        if fallback != preferred, UIImage(systemName: fallback) != nil {
            return fallback
        }

        return universalFallback
    }
}

enum Weekday: Int, Codable, CaseIterable, Identifiable {
    case monday = 1
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .monday:
            return "Monday"
        case .tuesday:
            return "Tuesday"
        case .wednesday:
            return "Wednesday"
        case .thursday:
            return "Thursday"
        case .friday:
            return "Friday"
        case .saturday:
            return "Saturday"
        case .sunday:
            return "Sunday"
        }
    }

    var shortName: String {
        switch self {
        case .monday:
            return "Mon"
        case .tuesday:
            return "Tue"
        case .wednesday:
            return "Wed"
        case .thursday:
            return "Thu"
        case .friday:
            return "Fri"
        case .saturday:
            return "Sat"
        case .sunday:
            return "Sun"
        }
    }
}

enum MetricRequirement: String, Codable, CaseIterable, Identifiable {
    case none
    case optional
    case required

    var id: String { rawValue }
}

enum ResistanceTrackingStyle: String, Codable, CaseIterable, Identifiable {
    case totalLoad
    case singleDumbbellPair

    var id: String { rawValue }

    var title: String {
        switch self {
        case .totalLoad:
            return "Total load"
        case .singleDumbbellPair:
            return "Single dumbbell"
        }
    }

    var editorDescription: String {
        switch self {
        case .totalLoad:
            return "Enter the full load for the set, like a barbell, machine stack, kettlebell, or one dumbbell."
        case .singleDumbbellPair:
            return "Enter the weight of one dumbbell. Marble will calculate the full resistance by doubling it."
        }
    }

    var fieldTitle: String {
        switch self {
        case .totalLoad:
            return "Weight"
        case .singleDumbbellPair:
            return "Single dumbbell"
        }
    }

    var loggerHelperText: String {
        switch self {
        case .totalLoad:
            return "Enter the total load you move for the set."
        case .singleDumbbellPair:
            return "Enter one dumbbell. Marble uses 2x this value for total resistance."
        }
    }

    func storedWeight(from inputWeight: Double?) -> Double? {
        guard let inputWeight else { return nil }
        switch self {
        case .totalLoad:
            return inputWeight
        case .singleDumbbellPair:
            return inputWeight * 2
        }
    }

    func inputWeight(from storedWeight: Double?) -> Double? {
        guard let storedWeight else { return nil }
        switch self {
        case .totalLoad:
            return storedWeight
        case .singleDumbbellPair:
            return storedWeight / 2
        }
    }
}

enum DistanceUnit: String, Codable, CaseIterable, Identifiable {
    case meters
    case yards
    case feet
    case kilometers
    case miles

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .meters:
            return "m"
        case .yards:
            return "yd"
        case .feet:
            return "ft"
        case .kilometers:
            return "km"
        case .miles:
            return "mi"
        }
    }

    var title: String {
        switch self {
        case .meters:
            return "Meters"
        case .yards:
            return "Yards"
        case .feet:
            return "Feet"
        case .kilometers:
            return "Kilometers"
        case .miles:
            return "Miles"
        }
    }
}

enum ExerciseMetricKind: String, CaseIterable, Identifiable {
    case weight
    case reps
    case distance
    case duration

    var id: String { rawValue }

    var editorTitle: String {
        switch self {
        case .weight:
            return "Resistance / load"
        case .reps:
            return "Reps"
        case .distance:
            return "Distance"
        case .duration:
            return "Duration"
        }
    }

    var shortTitle: String {
        switch self {
        case .weight:
            return "load"
        case .reps:
            return "reps"
        case .distance:
            return "distance"
        case .duration:
            return "duration"
        }
    }

    var optionalShortTitle: String {
        switch self {
        case .weight:
            return "added load"
        case .reps:
            return "reps"
        case .distance:
            return "distance"
        case .duration:
            return "duration"
        }
    }

    var editorDescription: String {
        switch self {
        case .weight:
            return "Use this for barbells, dumbbells, machine stacks, or extra weight added to bodyweight movements."
        case .reps:
            return "Use this when you count how many repetitions you perform in each set."
        case .distance:
            return "Use this for sprints, carries, intervals, or any movement where the length of the effort matters."
        case .duration:
            return "Use this for holds, carries, cardio intervals, recovery sessions, or any movement tracked by time."
        }
    }

    func helperText(for requirement: MetricRequirement) -> String {
        switch (self, requirement) {
        case (.weight, .none):
            return "Best for sit ups, crunches, or other movements where load never matters."
        case (.weight, .optional):
            return "Great for pull ups, dips, push ups, and other bodyweight moves where you only add load sometimes."
        case (.weight, .required):
            return "Best for strength movements where every logged set should always include a load."
        case (.reps, .none):
            return "Turn this off for holds, carries, recovery work, or sessions where counting reps adds friction."
        case (.reps, .optional):
            return "Use optional when some sets are timed and others are rep-based."
        case (.reps, .required):
            return "Most strength and hypertrophy exercises should require reps on every set."
        case (.distance, .none):
            return "Turn this off when the length of the effort never matters for this exercise."
        case (.distance, .optional):
            return "Use optional when you only track distance on certain sets or conditioning intervals."
        case (.distance, .required):
            return "Best for sprints, carries, sled pushes, and any movement where every set has a set distance."
        case (.duration, .none):
            return "Turn this off when time never matters for this exercise."
        case (.duration, .optional):
            return "Use optional when you only time certain sets or intervals."
        case (.duration, .required):
            return "Best for planks, hangs, carries, sauna, recovery, and other timed work."
        }
    }

    var optionalToggleTitle: String {
        switch self {
        case .weight:
            return "Added load"
        case .reps:
            return "Log reps for this set"
        case .distance:
            return "Log distance for this set"
        case .duration:
            return "Log duration for this set"
        }
    }
}

struct ExerciseMetricsProfile: Codable, Hashable {
    var weight: MetricRequirement
    var reps: MetricRequirement
    var distance: MetricRequirement
    var durationSeconds: MetricRequirement

    var usesWeight: Bool { weight != .none }
    var weightIsRequired: Bool { weight == .required }
    var usesReps: Bool { reps != .none }
    var repsIsRequired: Bool { reps == .required }
    var usesDistance: Bool { distance != .none }
    var distanceIsRequired: Bool { distance == .required }
    var usesDuration: Bool { durationSeconds != .none }
    var durationIsRequired: Bool { durationSeconds == .required }
    var hasAnyMetric: Bool { usesWeight || usesReps || usesDistance || usesDuration }

    init(
        weight: MetricRequirement,
        reps: MetricRequirement,
        distance: MetricRequirement = .none,
        durationSeconds: MetricRequirement
    ) {
        self.weight = weight
        self.reps = reps
        self.distance = distance
        self.durationSeconds = durationSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case weight
        case reps
        case distance
        case durationSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weight = try container.decode(MetricRequirement.self, forKey: .weight)
        reps = try container.decode(MetricRequirement.self, forKey: .reps)
        distance = try container.decodeIfPresent(MetricRequirement.self, forKey: .distance) ?? .none
        durationSeconds = try container.decode(MetricRequirement.self, forKey: .durationSeconds)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(weight, forKey: .weight)
        try container.encode(reps, forKey: .reps)
        try container.encode(distance, forKey: .distance)
        try container.encode(durationSeconds, forKey: .durationSeconds)
    }

    func requirement(for kind: ExerciseMetricKind) -> MetricRequirement {
        switch kind {
        case .weight:
            return weight
        case .reps:
            return reps
        case .distance:
            return distance
        case .duration:
            return durationSeconds
        }
    }

    mutating func setRequirement(_ requirement: MetricRequirement, for kind: ExerciseMetricKind) {
        switch kind {
        case .weight:
            weight = requirement
        case .reps:
            reps = requirement
        case .distance:
            distance = requirement
        case .duration:
            durationSeconds = requirement
        }
    }

    var requiredMetricKinds: [ExerciseMetricKind] {
        ExerciseMetricKind.allCases.filter { requirement(for: $0) == .required }
    }

    var optionalMetricKinds: [ExerciseMetricKind] {
        ExerciseMetricKind.allCases.filter { requirement(for: $0) == .optional }
    }

    func summaryText(
        defaultRestSeconds: Int? = nil,
        loadTrackingStyle: ResistanceTrackingStyle? = nil,
        distanceUnit: DistanceUnit? = nil
    ) -> String {
        var parts: [String] = []

        if !requiredMetricKinds.isEmpty {
            parts.append("Required: \(formatMetricList(requiredMetricKinds.map(\.shortTitle)))")
        }

        if !optionalMetricKinds.isEmpty {
            parts.append("Optional: \(formatMetricList(optionalMetricKinds.map(\.optionalShortTitle)))")
        }

        if usesWeight, let loadTrackingStyle, loadTrackingStyle == .singleDumbbellPair {
            parts.append("Enter one dumbbell")
        }

        if usesDistance, let distanceUnit {
            parts.append("Distance \(distanceUnit.symbol)")
        }

        if let defaultRestSeconds {
            parts.append("Rest \(DateHelper.formattedDuration(seconds: defaultRestSeconds))")
        }

        if parts.isEmpty {
            return "Choose at least one metric"
        }

        return parts.joined(separator: " · ")
    }

    var previewTitle: String {
        if !requiredMetricKinds.isEmpty {
            return "Logs \(formatMetricList(requiredMetricKinds.map(\.shortTitle)))"
        }

        if !optionalMetricKinds.isEmpty {
            return "Logs optional \(formatMetricList(optionalMetricKinds.map(\.optionalShortTitle)))"
        }

        return "Choose at least one metric"
    }

    var previewDescription: String {
        guard hasAnyMetric else {
            return "Turn on at least one metric so this exercise is easy to log later."
        }

        var sentences: [String] = []

        if !requiredMetricKinds.isEmpty {
            sentences.append("You'll enter \(formatMetricList(requiredMetricKinds.map(\.shortTitle))) on every set.")
        }

        if !optionalMetricKinds.isEmpty {
            sentences.append("\(capitalize(formatMetricList(optionalMetricKinds.map(\.optionalShortTitle)))) can be turned on only when needed.")
        }

        return sentences.joined(separator: " ")
    }

    private func formatMetricList(_ items: [String]) -> String {
        switch items.count {
        case 0:
            return ""
        case 1:
            return items[0]
        case 2:
            return "\(items[0]) and \(items[1])"
        default:
            let head = items.dropLast().joined(separator: ", ")
            return "\(head), and \(items.last ?? "")"
        }
    }

    private func capitalize(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    static let weightAndRepsRequired = ExerciseMetricsProfile(weight: .required, reps: .required, distance: .none, durationSeconds: .none)
    static let repsOnlyRequired = ExerciseMetricsProfile(weight: .none, reps: .required, distance: .none, durationSeconds: .none)
    static let durationOnlyRequired = ExerciseMetricsProfile(weight: .none, reps: .none, distance: .none, durationSeconds: .required)
    static let distanceAndDurationRequired = ExerciseMetricsProfile(weight: .none, reps: .none, distance: .required, durationSeconds: .required)
}

enum WeightUnit: String, Codable, CaseIterable, Identifiable {
    case lb
    case kg

    var id: String { rawValue }
    var symbol: String { rawValue }
}

enum SupplementUnit: String, Codable, CaseIterable, Identifiable {
    case g
    case scoop
    case serving
    case ml
    case count

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .g:
            return "g"
        case .scoop:
            return "scoop"
        case .serving:
            return "serving"
        case .ml:
            return "ml"
        case .count:
            return "count"
        }
    }
}

extension Exercise {
    var configurationSummaryText: String {
        metrics.summaryText(
            defaultRestSeconds: defaultRestSeconds,
            loadTrackingStyle: resistanceTrackingStyle,
            distanceUnit: preferredDistanceUnit
        )
    }
}
