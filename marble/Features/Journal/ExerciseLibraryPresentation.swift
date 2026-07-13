import Foundation

extension Exercise {
    func librarySummary(prescription: SprintPrescription?) -> String {
        if let prescription {
            return prescription.summary(
                distanceUnit: preferredDistanceUnit,
                restSeconds: defaultRestSeconds
            )
        }

        var parts: [String] = []
        for metric in ExerciseMetricKind.allCases where metrics.requirement(for: metric) == .required {
            parts.append(metric.libraryTitle)
        }
        for metric in ExerciseMetricKind.allCases where metrics.requirement(for: metric) == .optional {
            parts.append("\(metric.libraryTitle) optional")
        }
        if metrics.usesWeight, resistanceTrackingStyle == .singleDumbbellPair {
            parts.append("One dumbbell")
        }
        if metrics.usesDistance {
            parts.append(preferredDistanceUnit.symbol)
        }
        parts.append("\(DateHelper.formattedDuration(seconds: defaultRestSeconds)) rest")
        return parts.joined(separator: " · ")
    }
}

private extension ExerciseMetricKind {
    var libraryTitle: String {
        switch self {
        case .weight: "Weight"
        case .reps: "Reps"
        case .distance: "Distance"
        case .duration: "Time"
        }
    }
}
