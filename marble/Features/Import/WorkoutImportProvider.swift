import Foundation

enum ImportAuthorizationStatus: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    case needsConfiguration(String?)
}

protocol WorkoutImportProvider: Sendable {
    var source: ImportSource { get }
    func authorizationStatus() async -> ImportAuthorizationStatus
    func authorize() async throws
    func fetchWorkouts(in range: ClosedRange<Date>?) async throws -> [WorkoutImportRecord]
}
