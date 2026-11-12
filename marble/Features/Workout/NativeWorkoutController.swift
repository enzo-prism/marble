@preconcurrency import HealthKit
import Foundation
import Observation
import SwiftData

@MainActor
protocol NativeWorkoutFinishing: AnyObject {
    func finish() async
    func finish(for journalID: UUID) async
}

/// Opt-in HealthKit ownership of a live workout. The journal remains the source of
/// set history; HealthKit owns sensor collection, pauses and workout recovery.
@MainActor
@Observable
final class NativeWorkoutController: NSObject, NativeWorkoutFinishing, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    static let shared = NativeWorkoutController()
    nonisolated static let enabledKey = "marble.health.liveWorkouts"
    nonisolated static let sessionKey = "marble.health.activeSessionID"
    private(set) var heartRate: Double?
    private(set) var isPaused = false
    private(set) var isRunning = false
    private(set) var lastError: String?
    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var isFinishing = false
    @ObservationIgnored private var isCompleting = false
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var recoveryTask: Task<Void, Never>?
    #if DEBUG
    @ObservationIgnored private(set) var validationWorkout: HKWorkout?
    #endif
    private static var permitsSystemOperations: Bool {
        #if DEBUG
        if Bundle.main.object(forInfoDictionaryKey: "MarbleBundleSuffix") as? String == ".validation",
           (ProcessInfo.processInfo.environment["MARBLE_DEVICE_ACCEPTANCE"] == "1"
            || UserDefaults.standard.bool(forKey: "marble.validation.deviceAcceptance")) { return true }
        #endif
        return !TestHooks.isXCTestProcess && !TestHooks.isUITesting
    }
    @ObservationIgnored private var finishWaiters: [CheckedContinuation<Void, Never>] = []

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    func authorize() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: [.workoutType()], read: [.workoutType(), HKQuantityType(.heartRate)])
            return store.authorizationStatus(for: .workoutType()) == .sharingAuthorized
        } catch { return false }
    }

    func start(for journal: WorkoutSession) async {
        await recover()
        if let startTask { await startTask.value; return }
        guard journal.isActive, isEnabled, Self.permitsSystemOperations,
              session == nil, HKHealthStore.isHealthDataAvailable(),
              store.authorizationStatus(for: .workoutType()) == .sharingAuthorized else { return }
        let task = Task { await begin(journalID: journal.id, startedAt: journal.startedAt) }
        startTask = task
        await task.value
        startTask = nil
    }

    private func begin(journalID: UUID, startedAt: Date) async {
        do {
            let config = HKWorkoutConfiguration()
            config.activityType = .traditionalStrengthTraining
            config.locationType = .unknown
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            session.delegate = self
            builder.delegate = self
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            self.session = session
            self.builder = builder
            UserDefaults.standard.set(journalID.uuidString, forKey: Self.sessionKey)
            session.prepare()
            session.startActivity(with: startedAt)
            try await builder.beginCollection(at: startedAt)
            try await builder.addMetadata([
                HKMetadataKeySyncIdentifier: "Prism.marble.session.\(journalID.uuidString)",
                HKMetadataKeySyncVersion: NSNumber(value: 1)
            ])
            isRunning = true
            isPaused = false
            lastError = nil
        } catch {
            lastError = "Live Health tracking couldn't start. Your Marble workout is still being logged."
            self.session?.end()
            clearSession()
        }
    }

    func pause() {
        guard let session, isRunning, !isPaused else { return }
        session.pause()
        isPaused = true
        Task { await WorkoutActivityController.refresh() }
    }
    func resume() {
        guard let session, isRunning, isPaused else { return }
        session.resume()
        isPaused = false
        Task { await WorkoutActivityController.refresh() }
    }

    func finish() async {
        await startTask?.value
        if session == nil { await recover() }
        await finishCurrentSession()
    }

    /// Ends live Health tracking only when it belongs to this journal workout.
    /// A lost-ack finish retry must not stop a newer session's Health workout.
    func finish(for journalID: UUID) async {
        await startTask?.value
        if session == nil {
            guard Self.shouldFinish(journalID: journalID, liveSessionID: UserDefaults.standard.string(forKey: Self.sessionKey)) else { return }
            await recover()
        }
        guard Self.shouldFinish(journalID: journalID, liveSessionID: UserDefaults.standard.string(forKey: Self.sessionKey)) else { return }
        await finishCurrentSession()
    }

    /// `liveSessionID` is the journal UUID stored for the in-memory HealthKit session.
    nonisolated static func tracks(_ journalID: UUID, liveSessionID: String?) -> Bool {
        liveSessionID == journalID.uuidString
    }

    /// Skip recover/finish when the live Health session is a different workout.
    nonisolated static func shouldFinish(journalID: UUID, liveSessionID: String?) -> Bool {
        tracks(journalID, liveSessionID: liveSessionID)
    }

    /// Counts attempts to stop the in-memory Health session, including no-ops.
    @ObservationIgnored var finishCurrentSessionCalls = 0

    private func finishCurrentSession() async {
        finishCurrentSessionCalls += 1
        guard let session else { return }
        if session.state == .ended { clearSession(); return }
        await withCheckedContinuation { continuation in
            finishWaiters.append(continuation)
            if session.state == .stopped {
                Task { await complete() }
            } else if !isFinishing {
                isFinishing = true
                session.stopActivity(with: AppEnvironment.now)
            }
        }
    }

    func recover() async {
        if let recoveryTask { await recoveryTask.value; return }
        guard session == nil, startTask == nil, Self.permitsSystemOperations,
              UserDefaults.standard.string(forKey: Self.sessionKey) != nil else { return }
        let task = Task { await recoverSession() }
        recoveryTask = task
        await task.value
        recoveryTask = nil
    }

    private func recoverSession() async {
        do {
            let recovered = try await store.recoverActiveWorkoutSession()
            guard let recovered else { clearSession(); return }
            session = recovered
            builder = recovered.associatedWorkoutBuilder()
            recovered.delegate = self
            builder?.delegate = self
            builder?.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: recovered.workoutConfiguration)
            isRunning = recovered.state != .ended
            isPaused = recovered.state == .paused
            if recovered.state == .stopped { await complete() }
            else if recovered.state == .ended { clearSession() }
            else {
                let journalID = UserDefaults.standard.string(forKey: Self.sessionKey)
                let journalMatches = AppIntentsSupport.container.map {
                    WorkoutSessionIntentSupport.activeSession(in: $0.mainContext)?.id.uuidString == journalID
                } ?? true
                if !isEnabled || !journalMatches { await finish() }
            }
        } catch {
            lastError = "Couldn't reconnect to live Health tracking. Your Marble sets are saved."
        }
    }

    private func complete() async {
        guard !isCompleting, let session, let builder else { return }
        isCompleting = true
        do {
            let now = AppEnvironment.now
            try await builder.endCollection(at: now)
            let saved = try await builder.finishWorkout()
            #if DEBUG
            if Bundle.main.object(forInfoDictionaryKey: "MarbleBundleSuffix") as? String == ".validation" {
                validationWorkout = saved
            }
            #endif
            guard self.session === session else { return }
            lastError = nil
        } catch {
            guard self.session === session else { return }
            lastError = "Apple Health hasn't finished saving this workout. Your Marble sets remain saved."
        }
        session.end()
        clearSession()
    }

    private func clearSession() {
        session = nil
        builder = nil
        isRunning = false
        isPaused = false
        heartRate = nil
        isFinishing = false
        isCompleting = false
        UserDefaults.standard.removeObject(forKey: Self.sessionKey)
        let waiters = finishWaiters
        finishWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor [weak self] in
            guard let self, self.session === workoutSession else { return }
            if toState == .stopped { await self.complete() }
            else if toState == .paused { self.isPaused = true }
            else if toState == .running { self.isPaused = false }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.session === workoutSession else { return }
            self.lastError = "Live Health tracking stopped. Your Marble workout and sets remain available."
            self.clearSession()
        }
    }
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard collectedTypes.contains(HKQuantityType(.heartRate)),
              let value = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) else { return }
        Task { @MainActor [weak self] in
            guard let self, self.builder === workoutBuilder else { return }
            self.heartRate = value
        }
    }
}
