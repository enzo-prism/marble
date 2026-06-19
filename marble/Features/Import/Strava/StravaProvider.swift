import Foundation

@MainActor
final class StravaProvider: WorkoutImportProvider {
    let source: ImportSource = .strava
    private let client: StravaClient

    init(client: StravaClient) {
        self.client = client
    }

    func authorizationStatus() async -> ImportAuthorizationStatus {
        guard client.configuration.isConfigured else { return .needsConfiguration(nil) }
        return client.hasToken ? .authorized : .notDetermined
    }

    func authorize() async throws {
        try await client.authorize()
    }

    func disconnect() {
        client.disconnect()
    }

    func fetchWorkouts(in range: ClosedRange<Date>?) async throws -> [WorkoutImportRecord] {
        let activities = try await client.fetchActivities(start: range?.lowerBound, end: range?.upperBound)
        return activities.compactMap { Self.record(from: $0) }
    }

    // MARK: - Mapping

    /// Returns `nil` for activities we can't import safely — no stable id (can't
    /// deduplicate) or no parseable timestamp (would be backdated to "now").
    static func record(from activity: StravaActivity) -> WorkoutImportRecord? {
        guard let id = activity.id else { return nil }
        guard let date = parseDate(activity.startDate) else { return nil }

        let sportType = activity.sportType ?? activity.type ?? ""
        let hasDistance = (activity.distance ?? 0) > 0
        let kind = activityKind(for: sportType, hasDistance: hasDistance)

        let title: String = {
            let trimmed = activity.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty { return trimmed }
            return kind.displayName
        }()

        // Strava reports both moving and elapsed time; prefer moving time (the active
        // effort), falling back to elapsed.
        let duration = activity.movingTime ?? activity.elapsedTime

        return WorkoutImportRecord(
            source: .strava,
            externalID: String(id),
            date: date,
            title: title,
            kind: kind,
            distanceMeters: activity.distance,
            durationSeconds: duration,
            calories: nil,
            averageHeartRate: activity.averageHeartrate,
            strengthSets: []
        )
    }

    static func activityKind(for sportType: String, hasDistance: Bool) -> ImportedActivityKind {
        switch sportType.lowercased() {
        case "run", "trailrun", "virtualrun", "treadmill":
            return .running
        case "ride", "virtualride", "mountainbikeride", "gravelride", "ebikeride", "handcycle", "velomobile":
            return .cycling
        case "swim":
            return .swimming
        case "hike":
            return .hiking
        case "walk":
            return .walking
        case "weighttraining", "crossfit":
            return .strength
        default:
            return hasDistance ? .otherCardio : .other
        }
    }

    static func parseDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: string) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: string)
    }
}
