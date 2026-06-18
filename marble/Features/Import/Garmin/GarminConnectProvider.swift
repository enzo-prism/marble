import Foundation
import AuthenticationServices
import UIKit

@MainActor
final class GarminConnectProvider: WorkoutImportProvider {
    let source: ImportSource = .garminConnect
    private let client: GarminConnectClient
    private let presentationContext = WebAuthPresentationContext()
    private var activeSession: ASWebAuthenticationSession?

    init(client: GarminConnectClient) {
        self.client = client
    }

    func authorizationStatus() async -> ImportAuthorizationStatus {
        guard client.configuration.isConfigured else { return .needsConfiguration(nil) }
        return client.hasToken ? .authorized : .notDetermined
    }

    func authorize() async throws {
        guard let url = client.authorizationURL else { throw GarminConnectError.notConfigured }
        let scheme = URL(string: client.configuration.redirectURI)?.scheme

        let code: String = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { [weak self] callbackURL, error in
                self?.activeSession = nil
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: GarminConnectError.unauthorized)
                    return
                }
                let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
                let code = components?.queryItems?.first(where: { $0.name == "code" })?.value
                if let code {
                    continuation.resume(returning: code)
                } else {
                    continuation.resume(throwing: GarminConnectError.unauthorized)
                }
            }
            session.presentationContextProvider = self.presentationContext
            session.prefersEphemeralWebBrowserSession = false
            self.activeSession = session
            session.start()
        }

        try await client.completeAuthorization(code: code)
    }

    func fetchWorkouts(in range: ClosedRange<Date>?) async throws -> [WorkoutImportRecord] {
        let activities = try await client.fetchActivities(start: range?.lowerBound, end: range?.upperBound)
        return activities.map { Self.record(from: $0) }
    }

    func disconnect() {
        client.disconnect()
    }

    static func record(from activity: GarminActivity) -> WorkoutImportRecord {
        let typeKey = activity.activityType?.typeKey ?? ""
        let kind = activityKind(for: typeKey, hasDistance: (activity.distance ?? 0) > 0)
        let date = parseDate(activity.startTimeGMT) ?? Date()
        let title: String = {
            let trimmed = activity.activityName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty { return trimmed }
            return kind.displayName
        }()

        return WorkoutImportRecord(
            source: .garminConnect,
            externalID: String(activity.activityId ?? 0),
            date: date,
            title: title,
            kind: kind,
            distanceMeters: activity.distance,
            durationSeconds: activity.duration.map { Int($0.rounded()) },
            calories: activity.calories,
            averageHeartRate: activity.averageHR,
            strengthSets: []
        )
    }

    static func activityKind(for typeKey: String, hasDistance: Bool) -> ImportedActivityKind {
        switch typeKey.lowercased() {
        case "running", "treadmill_running", "trail_running":
            return .running
        case "cycling", "road_biking", "mountain_biking", "cyclocross", "indoor_cycling":
            return .cycling
        case "swimming", "lap_swimming", "open_water_swimming":
            return .swimming
        case "hiking":
            return .hiking
        case "walking":
            return .walking
        case "strength_training", "fitness_equipment":
            return .strength
        default:
            return hasDistance ? .otherCardio : .other
        }
    }

    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

@MainActor
final class WebAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { !$0.windows.isEmpty }
        return scene?.windows.first ?? ASPresentationAnchor()
    }
}
