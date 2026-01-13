import Foundation

enum ExerciseCategory: String, Codable, CaseIterable, Identifiable {
    case chest
    case shoulders
    case legs
    case power
    case back
    case core
    case bar
    case recover
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest:
            return "Chest"
        case .shoulders:
            return "Shoulders"
        case .legs:
            return "Legs"
        case .power:
            return "Power"
        case .back:
            return "Back"
        case .core:
            return "Core"
        case .bar:
            return "Bar"
        case .recover:
            return "Recover"
        case .other:
            return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .chest:
            return "heart.fill"
        case .shoulders:
            return "figure.strengthtraining.traditional"
        case .legs:
            return "figure.walk"
        case .power:
            return "bolt.fill"
        case .back:
            return "arrow.triangle.2.circlepath"
        case .core:
            return "circle.grid.cross"
        case .bar:
            return "figure.gymnastics"
        case .recover:
            if #available(iOS 17.0, *) {
                return "sauna"
            } else {
                return "flame.fill"
            }
        case .other:
            return "circle.dashed"
        }
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

struct ExerciseMetricsProfile: Codable, Hashable {
    var weight: MetricRequirement
    var reps: MetricRequirement
    var durationSeconds: MetricRequirement

    var usesWeight: Bool { weight != .none }
    var weightIsRequired: Bool { weight == .required }
    var usesReps: Bool { reps != .none }
    var repsIsRequired: Bool { reps == .required }
    var usesDuration: Bool { durationSeconds != .none }
    var durationIsRequired: Bool { durationSeconds == .required }

    static let weightAndRepsRequired = ExerciseMetricsProfile(weight: .required, reps: .required, durationSeconds: .none)
    static let repsOnlyRequired = ExerciseMetricsProfile(weight: .none, reps: .required, durationSeconds: .none)
    static let durationOnlyRequired = ExerciseMetricsProfile(weight: .none, reps: .none, durationSeconds: .required)
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
