import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.undoManager) private var undoManager

    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt == nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var activeSessions: [WorkoutSession]

    @State private var quickLog = QuickLogCoordinator()
    @State private var tabSelection = TabSelection()
    @State private var activeDay = DateHelper.startOfDay(for: AppEnvironment.now)
    @State private var persistenceIssues = PersistenceIssueCenter.shared
    @State private var showingOnboarding = false

    private let restTimer = RestActivityController.shared

    var body: some View {
        TabView(selection: $tabSelection.selected) {
            JournalView()
                .tabItem {
                    Label("Journal", systemImage: "list.bullet.rectangle")
                        .accessibilityIdentifier("Tab.Journal")
                }
                .tag(AppTab.journal)

            CalendarView()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                        .accessibilityIdentifier("Tab.Calendar")
                }
                .tag(AppTab.calendar)

            WorkoutView()
                .tabItem {
                    Label("Workout", systemImage: "figure.strengthtraining.traditional")
                        .accessibilityIdentifier("Tab.Split")
                }
                .tag(AppTab.split)

            SupplementsView()
                .tabItem {
                    Label("Supplements", systemImage: "pills")
                        .accessibilityIdentifier("Tab.Supplements")
                }
                .tag(AppTab.supplements)

            TrendsView()
                .tabItem {
                    Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
                        .accessibilityIdentifier("Tab.Trends")
                }
                .tag(AppTab.trends)
        }
        .marbleRestPillAccessory(rest: restTimer.activeRest) {
            RestActivityController.shared.cancelRest()
        }
        .environment(tabSelection)
        .environment(quickLog)
        .environment(\.marbleActiveDay, activeDay)
        .tabBarGlassBackground()
        .marbleTabBarMinimizeBehavior()
        .tint(Theme.primaryTextColor(for: colorScheme))
        .onAppear {
            Theme.applyTabBarAppearance(for: colorScheme)
        }
        .onChange(of: colorScheme) { _, newScheme in
            Theme.applyTabBarAppearance(for: newScheme)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshActiveDay()
                // ActivityKit outlives this app process. Reconcile the complete system
                // inventory so an expired or duplicated Lock Screen timer cannot survive a
                // suspension/relaunch, and recover the one valid timer if it still exists.
                restTimer.reconcileLiveActivities()
                // Pull any workouts that landed in Apple Health while we were
                // away (no-op unless the user enabled auto-import).
                Task { await HealthAutoImportService.shared.syncIfEnabled(into: modelContext) }
                // Same anchored-query pattern, bodyweight stream (opt-in).
                Task { await BodyMetricsAutoImportService.shared.syncIfEnabled(into: modelContext) }
            }
            if newPhase == .active || newPhase == .background {
                // Keep the weekly-goal nudge honest: reschedule against what
                // was actually logged, cancel it once the target is hit.
                Task { await WeeklyGoalReminder.sync(modelContext: modelContext) }
                // Refresh Apple Health session export (no-op unless enabled).
                Task { await HealthSessionExporter.shared.exportIfEnabled(from: modelContext) }
                // Push the same consistency numbers out to the Home/Lock Screen
                // widget. Backgrounding is the important half: it is the last
                // moment we can refresh before the user looks at the widget.
                WeeklyGoalWidgetPublisher.publish(modelContext: modelContext)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            refreshActiveDay()
        }
        .onReceive(NotificationCenter.default.publisher(for: .marbleOpenQuickLog)) { _ in
            quickLog.open()
        }
        .onOpenURL { url in
            // Widget deep links (`marble://trends`). Widget URLs are delivered
            // straight to the owning app, so the scheme needs no Info.plist
            // registration — but we still check it before acting on a host.
            guard url.scheme == "marble", let tab = Self.tab(for: url.host) else { return }
            tabSelection.selected = tab
        }
        .sheet(isPresented: $quickLog.isPresentingAddSet, onDismiss: {
            quickLog.clearPresentationContext()
        }) {
            AddSetView(
                initialPerformedAt: quickLog.prefillDate,
                initialExercise: fetchExercise(id: quickLog.prefillExerciseID),
                context: quickLog.context,
                activeSession: fetchWorkoutSession(id: quickLog.workoutSessionID) ?? activeSessions.first,
                isPresented: $quickLog.isPresentingAddSet
            )
                .modelContext(modelContext)
                .environment(quickLog)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .sheetGlassBackground()
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView {
                showingOnboarding = false
            }
        }
        .background(Theme.backgroundColor(for: colorScheme))
        .alert("Unable to Save", isPresented: Binding(
            get: { persistenceIssues.message != nil },
            set: { if !$0 { persistenceIssues.message = nil } }
        )) {
            Button("OK", role: .cancel) {}
                .accessibilityIdentifier("Persistence.Error.OK")
        } message: {
            Text(persistenceIssues.message ?? "Please try again.")
        }
        .applyTestOverrides()
        .task {
            // `scenePhase` does not necessarily transition on a cold launch, so perform the
            // same ActivityKit recovery here as well. This also cleans piles created by older
            // builds the first time the fixed app opens.
            restTimer.reconcileLiveActivities()
            // Routes the system undo gestures (shake, three-finger swipe)
            // through SwiftData's change tracking.
            modelContext.undoManager = undoManager
            // Gate is pure and tested (OnboardingGateTests). Existing users
            // upgrading to 2.2 are skipped AND stamped complete, so the flow
            // can never surface for them on a later launch. The seed flag it
            // reads is the one captured in `MarbleApp.init()`, so this task no
            // longer races the seeding task in `marbleApp`.
            // Puts the exercise library in Spotlight's semantic index, which is
            // how the rebuilt Siri reaches app content.
            Task { await ExerciseSpotlightIndex.reindexAll() }
            let onboarding = OnboardingGate.currentDecision()
            if onboarding.marksCompleteSilently {
                OnboardingGate.markComplete()
            }
            // Stamped before the cover appears, so force-quitting on page 2
            // resumes onboarding next launch instead of losing it forever.
            if onboarding.recordsOnboardingStarted {
                OnboardingGate.markBegun()
            }
            showingOnboarding = onboarding.presentsOnboarding
            if TestHooks.isUITesting {
                if let tab = Self.tab(for: TestHooks.initialTab) {
                    tabSelection.selected = tab
                } else if TestHooks.calendarTestDay != nil {
                    tabSelection.selected = .calendar
                }
                if TestHooks.openQuickLogAtLaunch {
                    quickLog.open()
                }
            }
        }
        .onChange(of: undoManager) { _, newValue in
            modelContext.undoManager = newValue
        }
    }

    private static func tab(for identifier: String?) -> AppTab? {
        switch identifier {
        case "journal":
            return .journal
        case "calendar":
            return .calendar
        case "split":
            return .split
        case "supplements":
            return .supplements
        case "trends":
            return .trends
        default:
            return nil
        }
    }

    private func refreshActiveDay() {
        let day = DateHelper.startOfDay(for: AppEnvironment.now)
        if day != activeDay {
            activeDay = day
        }
    }

    private func fetchExercise(id: UUID?) -> Exercise? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func fetchWorkoutSession(id: UUID?) -> WorkoutSession? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id })
        return (try? modelContext.fetch(descriptor))?.first
    }
}

#Preview {
    ContentView()
}
