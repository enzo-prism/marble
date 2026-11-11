import SwiftUI
import UserNotifications
import WatchKit
@preconcurrency import WatchConnectivity

@main
struct MarbleWatchApp: App {
    @State private var connection = WatchWorkoutConnection()
    var body: some Scene {
        WindowGroup { WatchWorkoutView(connection: connection) }
    }
}

@MainActor
@Observable
final class WatchWorkoutConnection: NSObject, WCSessionDelegate {
    private(set) var snapshot: WatchWorkoutSnapshot?
    private(set) var isSending = false
    private(set) var message: String?
    private(set) var isReachable = false
    @ObservationIgnored private var pendingRequest: WatchWorkoutRequest?
    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        if let saved = UserDefaults.standard.data(forKey: "marble.watch.snapshot") {
            snapshot = try? JSONDecoder().decode(WatchWorkoutSnapshot.self, from: saved)
        }
        if let pending = UserDefaults.standard.data(forKey: "marble.watch.pendingRequest") {
            pendingRequest = try? JSONDecoder().decode(WatchWorkoutRequest.self, from: pending)
        }
    }
    func send(_ action: WatchWorkoutRequest.Action) {
        guard !isSending else { return }
        guard WCSession.default.isReachable else {
            isReachable = false
            message = "Open Marble on your iPhone to reconnect."
            return
        }
        if pendingRequest != nil, action != .refresh { message = "Retry the pending request first."; return }
        let request = action == .refresh ? WatchWorkoutRequest(id: UUID(), action: action,
            sessionID: nil, setID: nil, createdAt: Date()) : WatchWorkoutRequest(id: UUID(), action: action,
                sessionID: snapshot?.sessionID, setID: snapshot?.lastSetID, createdAt: Date())
        perform(request)
    }
    var hasPendingRequest: Bool { pendingRequest != nil }
    func retry() { if let pendingRequest { perform(pendingRequest) } }
    private func perform(_ request: WatchWorkoutRequest) {
        guard !isSending, WCSession.default.isReachable,
              let data = try? JSONEncoder().encode(request) else { return }
        if request.action != .refresh {
            pendingRequest = request
            UserDefaults.standard.set(data, forKey: "marble.watch.pendingRequest")
        }
        isSending = true
        WCSession.default.sendMessageData(data) { data in
            Task { @MainActor in
                self.isSending = false
                guard let result = try? JSONDecoder().decode(WatchWorkoutResponse.self, from: data) else {
                    self.message = "No confirmation received. Retry to check."; return
                }
                if request.action != .refresh {
                    self.pendingRequest = nil
                    UserDefaults.standard.removeObject(forKey: "marble.watch.pendingRequest")
                }
                if let snapshot = result.snapshot { self.receive(snapshot) }
                self.message = result.message
                if result.succeeded, request.action != .refresh { WKInterfaceDevice.current().play(.success) }
                else if !result.succeeded { WKInterfaceDevice.current().play(.failure) }
            }
        } errorHandler: { _ in
            Task { @MainActor in
                self.isSending = false
                self.message = "Couldn't confirm. Reconnect and retry before logging again."
            }
        }
    }
    private func receive(_ snapshot: WatchWorkoutSnapshot) {
        guard self.snapshot == nil || snapshot.updatedAt >= self.snapshot!.updatedAt else { return }
        self.snapshot = snapshot
        UserDefaults.standard.set(try? JSONEncoder().encode(snapshot), forKey: "marble.watch.snapshot")
        scheduleRestAlert(snapshot.restEndsAt)
    }
    func enableRestAlerts() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        scheduleRestAlert(snapshot?.restEndsAt)
    }
    private func scheduleRestAlert(_ end: Date?) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["marble.watch.rest"])
        guard let end, end > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "Ready for your next set in Marble."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: "marble.watch.rest", content: content, trigger: trigger))
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let data = session.receivedApplicationContext["workout"] as? Data
        Task { @MainActor in
            self.isReachable = WCSession.default.isReachable
            if let data, let snapshot = try? JSONDecoder().decode(WatchWorkoutSnapshot.self, from: data) { self.receive(snapshot) }
            self.send(.refresh)
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["workout"] as? Data,
              let snapshot = try? JSONDecoder().decode(WatchWorkoutSnapshot.self, from: data) else { return }
        Task { @MainActor in self.receive(snapshot) }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.isReachable = WCSession.default.isReachable }
    }
}

struct WatchWorkoutView: View {
    let connection: WatchWorkoutConnection
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmsFinish = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let snapshot = connection.snapshot, snapshot.sessionID != nil {
                        Text(snapshot.title).font(.headline)
                        if let start = snapshot.startedAt { Text(start, style: .timer).monospacedDigit() }
                        Text("\(snapshot.setCount) sets").font(.caption)
                        if let exercise = snapshot.exerciseName { Text(exercise).fixedSize(horizontal: false, vertical: true) }
                        if let end = snapshot.restEndsAt, end > Date() {
                            Text(timerInterval: Date()...end, countsDown: true).monospacedDigit()
                        }
                        Button("Repeat Last Set") { connection.send(.repeatSet) }
                            .disabled(snapshot.lastSetID == nil)
                            .accessibilityIdentifier("Watch.RepeatSet")
                        Button("Rest 90 Seconds") { connection.send(.startRest) }.accessibilityIdentifier("Watch.StartRest")
                        Button("Skip Rest") { connection.send(.skipRest) }.accessibilityIdentifier("Watch.SkipRest")
                        Button("Finish Workout") { confirmsFinish = true }.accessibilityIdentifier("Watch.Finish")
                    } else {
                        Text("Log with your iPhone").font(.headline)
                        Text("Start a workout here, then log your first set in Marble on iPhone.").font(.caption)
                        Button("Start Workout") { connection.send(.start) }.accessibilityIdentifier("Watch.Start")
                    }
                    if connection.hasPendingRequest {
                        Button("Retry Pending Request") { connection.retry() }.accessibilityIdentifier("Watch.Retry")
                    }
                    if let message = connection.message { Text(message).font(.caption).fixedSize(horizontal: false, vertical: true) }
                    if !connection.isReachable { Text("iPhone disconnected").font(.caption) }
                    Button("Refresh") { connection.send(.refresh) }.accessibilityIdentifier("Watch.Refresh")
                    Button("Enable Rest Alerts") { Task { await connection.enableRestAlerts() } }.accessibilityIdentifier("Watch.RestAlerts")
                }
                .buttonStyle(.bordered)
                .disabled(connection.isSending)
                .padding(.horizontal)
            }
            .navigationTitle("Marble")
            .confirmationDialog("Finish workout?", isPresented: $confirmsFinish) {
                Button("Finish") { connection.send(.finish) }.accessibilityIdentifier("Watch.Finish.Confirm")
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { connection.send(.refresh) } }
        }
        .tint(.primary)
    }
}
