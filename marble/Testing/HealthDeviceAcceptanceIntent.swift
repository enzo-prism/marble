#if DEBUG
import AppIntents
import HealthKit
import SwiftData

/// Explicitly gated hardware acceptance; never present in Release. It creates
/// and removes only a validation-owned workout, never existing Health history.
struct HealthDeviceAcceptanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Validate Native Workout Tracking"
    static let isDiscoverable = false
    static let openAppWhenRun = true
    @Parameter(title: "Action") var action: String
    private static let sessionKey = "marble.validation.healthSession"
    private static let previousEnabledKey = "marble.validation.previousHealthEnabled"

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard Bundle.main.object(forInfoDictionaryKey: "MarbleBundleSuffix") as? String == ".validation",
              (ProcessInfo.processInfo.environment["MARBLE_DEVICE_ACCEPTANCE"] == "1"
               || UserDefaults.standard.bool(forKey: "marble.validation.deviceAcceptance")) else {
            throw WorkoutIntentFailure(message: "Requires the isolated device-acceptance installation.")
        }
        let controller = NativeWorkoutController.shared
        let context = try AppIntentsSupport.resolvedContainer().mainContext
        TestHooks.overrideNow = Date()
        var authorized = HKHealthStore().authorizationStatus(for: .workoutType()) == .sharingAuthorized
        switch action {
        case "prepare":
            UserDefaults.standard.set(controller.isEnabled, forKey: Self.previousEnabledKey)
            UserDefaults.standard.set(true, forKey: "marble.validation.deviceAcceptance")
        case "authorize":
            UserDefaults.standard.set(true, forKey: "marble.validation.deviceAcceptance")
            authorized = await controller.authorize()
        case "start":
            guard WorkoutSessionIntentSupport.activeSession(in: context) == nil else {
                throw WorkoutIntentFailure(message: "Preserving an existing validation workout.")
            }
            if UserDefaults.standard.object(forKey: Self.previousEnabledKey) == nil {
                UserDefaults.standard.set(controller.isEnabled, forKey: Self.previousEnabledKey)
            }
            UserDefaults.standard.set(true, forKey: NativeWorkoutController.enabledKey)
            guard let session = WorkoutCommands.start(in: context, title: "Marble Validation — Health Acceptance") else {
                throw WorkoutIntentFailure(message: "Couldn't create validation journal session.")
            }
            UserDefaults.standard.set(session.id.uuidString, forKey: Self.sessionKey)
            await controller.start(for: session)
        case "pause": controller.pause()
        case "resume": controller.resume()
        case "finish":
            if let session = WorkoutSessionIntentSupport.activeSession(in: context) {
                guard session.id.uuidString == UserDefaults.standard.string(forKey: Self.sessionKey), session.entries.isEmpty else {
                    throw WorkoutIntentFailure(message: "Validation session identity changed.")
                }
                guard WorkoutCommands.finish(session, in: context) else { throw WorkoutIntentFailure(message: "Couldn't finish validation session.") }
            }
            await controller.finish()
        case "cleanup":
            await controller.finish()
            let store = HKHealthStore()
            if let text = UserDefaults.standard.string(forKey: Self.sessionKey),
               let saved = controller.validationWorkout,
               saved.metadata?[HKMetadataKeySyncIdentifier] as? String == "Prism.marble.session.\(text)",
               saved.sourceRevision.source.bundleIdentifier == "Prism.marble.validation" {
                try await store.delete(saved)
            } else if let text = UserDefaults.standard.string(forKey: Self.sessionKey) {
                // A process restart can lose the returned object. Recover only
                // this exact validation sync identity, never a date-range delete.
                let identifier = "Prism.marble.session.\(text)"
                let samples: [HKSample] = try await withCheckedThrowingContinuation { continuation in
                    let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [identifier])
                    store.execute(HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 10, sortDescriptors: nil) { _, samples, error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume(returning: samples ?? []) }
                    })
                }
                for sample in samples where sample.sourceRevision.source.bundleIdentifier == "Prism.marble.validation" { try await store.delete(sample) }
            }
            if let text = UserDefaults.standard.string(forKey: Self.sessionKey), let id = UUID(uuidString: text),
               let session = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id })).first {
                guard session.entries.isEmpty, session.title == "Marble Validation — Health Acceptance" else {
                    throw WorkoutIntentFailure(message: "Preserving changed validation data.")
                }
                context.delete(session)
                try context.save()
            }
            UserDefaults.standard.set(UserDefaults.standard.bool(forKey: Self.previousEnabledKey), forKey: NativeWorkoutController.enabledKey)
            UserDefaults.standard.removeObject(forKey: Self.sessionKey)
            UserDefaults.standard.removeObject(forKey: Self.previousEnabledKey)
            UserDefaults.standard.removeObject(forKey: "marble.validation.deviceAcceptance")
            TestHooks.overrideNow = nil
        case "status": break
        default: throw WorkoutIntentFailure(message: "Unknown validation action.")
        }
        let result: [String: Any] = ["authorized": authorized, "running": controller.isRunning,
            "paused": controller.isPaused, "saved": controller.validationWorkout != nil,
            "error": controller.lastError ?? ""]
        return .result(value: String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self))
    }
}
#endif
