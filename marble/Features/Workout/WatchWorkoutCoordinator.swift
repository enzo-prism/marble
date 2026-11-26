import Foundation
import SwiftData
@preconcurrency import WatchConnectivity

@MainActor
final class WatchWorkoutCoordinator: NSObject, WCSessionDelegate {
    static let shared = WatchWorkoutCoordinator()
    #if DEBUG
    var nativeWorkout: any NativeWorkoutFinishing = NativeWorkoutController.shared
    #else
    private(set) var nativeWorkout: any NativeWorkoutFinishing = NativeWorkoutController.shared
    #endif
    private var activated = false
    func activate() {
        guard !activated, !TestHooks.isUITesting, !TestHooks.isXCTestProcess, WCSession.isSupported() else { return }
        activated = true
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    func publish() {
        guard activated, WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled,
              let snapshot = snapshot(), let data = try? JSONEncoder().encode(snapshot) else { return }
        try? WCSession.default.updateApplicationContext(["workout": data])
    }
    private func snapshot() -> WatchWorkoutSnapshot? {
        guard let context = AppIntentsSupport.container?.mainContext else { return nil }
        let session = WorkoutSessionIntentSupport.activeSession(in: context)
        return WatchWorkoutSnapshot(sessionID: session?.id, title: session?.title ?? "Marble",
            startedAt: session?.startedAt, lastSetID: session?.orderedEntries.last?.id,
            exerciseName: session?.orderedEntries.last?.exercise.name, setCount: session?.entries.count ?? 0,
            restEndsAt: RestActivityController.shared.activeRest?.endsAt, updatedAt: AppEnvironment.now)
    }

    /// Requests carry explicit workout/set identity. A repeat uses its request UUID
    /// as the persistent SetEntry ID, so a lost acknowledgement cannot duplicate it.
    func handle(_ request: WatchWorkoutRequest) async -> WatchWorkoutResponse {
        func response(_ succeeded: Bool, _ message: String, retryable: Bool = false) -> WatchWorkoutResponse {
            .init(succeeded: succeeded, message: message, snapshot: snapshot(), retryable: retryable)
        }
        guard let context = AppIntentsSupport.container?.mainContext else {
            return response(false, "Open Marble on your iPhone first.", retryable: true)
        }
        if request.action == .refresh { return response(true, "Updated") }
        if request.action == .repeatSet {
            let id = request.id
            if let entry = try? context.fetch(FetchDescriptor<SetEntry>(predicate: #Predicate { $0.id == id })).first {
                return response(true, "Logged \(entry.exercise.name)")
            }
        }
        // A lost start/finish acknowledgement retries the same request ID
        // against work that is already saved. Treat that as success before
        // expiry so the Watch can drop the pending ID.
        if request.action == .start {
            let id = request.id
            if let _ = try? context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id })).first {
                return response(true, "Workout request already saved")
            }
        }
        if request.action == .finish, let sessionID = request.sessionID {
            if let existing = try? context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID })).first,
               existing.endedAt != nil {
                await finishCompanionSurfaces(sessionID: existing.id, from: context)
                await AppIntentsSupport.refreshSystemSurfaces(modelContext: context)
                publish()
                return response(true, "Workout already finished")
            }
        }
        guard abs(request.createdAt.timeIntervalSince(AppEnvironment.now)) <= 120 else {
            return response(false, "That request expired. Refresh and try again.")
        }
        let session = WorkoutSessionIntentSupport.activeSession(in: context)
        if request.action == .start {
            guard session == nil else { return response(true, "Workout already running") }
            guard let created = WorkoutCommands.start(in: context, requestID: request.id) else {
                return response(false, "Couldn't start workout", retryable: true)
            }
            await NativeWorkoutController.shared.start(for: created)
        } else {
            guard let session, session.id == request.sessionID else { return response(false, "Workout changed. Refresh before logging.") }
            switch request.action {
            case .repeatSet:
                guard let source = session.orderedEntries.last, source.id == request.setID else {
                    return response(false, "Latest set changed. Refresh before repeating.")
                }
                guard WorkoutCommands.repeatSet(source, into: session, requestID: request.id, in: context) != nil else {
                    return response(false, "Couldn't save set", retryable: true)
                }
            case .startRest:
                let end = request.createdAt.addingTimeInterval(90)
                guard end > AppEnvironment.now else { return response(false, "Rest request expired") }
                RestActivityController.shared.startRest(exerciseName: session.orderedEntries.last?.exercise.name ?? session.title,
                    restSeconds: Int(ceil(end.timeIntervalSince(AppEnvironment.now))))
            case .skipRest: RestActivityController.shared.cancelRest()
            case .finish:
                guard WorkoutCommands.finish(session, in: context) else {
                    return response(false, "Couldn't finish workout", retryable: true)
                }
                await finishCompanionSurfaces(sessionID: session.id, from: context)
            case .start, .refresh: break
            }
        }
        await AppIntentsSupport.refreshSystemSurfaces(modelContext: context)
        publish()
        return response(true, request.action == .repeatSet ? "Set saved" : "Updated")
    }

    /// Native Health finish is scoped to this journal workout so a lost-ack
    /// retry cannot stop a newer live session. Export remains idempotent.
    private func finishCompanionSurfaces(sessionID: UUID, from context: ModelContext) async {
        await nativeWorkout.finish(for: sessionID)
        await HealthSessionExporter.shared.exportIfEnabled(from: context)
    }

    private nonisolated struct Reply: @unchecked Sendable { let send: (Data) -> Void }
    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {
        let reply = Reply(send: replyHandler)
        guard let request = try? JSONDecoder().decode(WatchWorkoutRequest.self, from: messageData) else {
            reply.send(Data()); return
        }
        Task { @MainActor in
            let response = await self.handle(request)
            reply.send((try? JSONEncoder().encode(response)) ?? Data())
        }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.publish() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { Task { @MainActor in self.publish() } }
}
