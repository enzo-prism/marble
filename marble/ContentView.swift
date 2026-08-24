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
    @State private var showingActiveWorkout = false
    @Namespace private var logSetZoom

    private let restTimer = RestActivityController.shared

    var body: some View {
        TabView(selection: tabBarSelection) {
            WorkoutTextEntryView(
                presentation: .primaryTab,
                onShowJournal: { tabSelection.selectLogMode(.journal) }
            )
                .tabItem {
                    Label("Add", systemImage: "square.and.pencil")
                        .accessibilityIdentifier("Tab.Add")
                }
                .tag(AppTab.addWorkout)

            LogHubView()
                .tabItem {
                    Label("Log", systemImage: "list.bullet.rectangle")
                        .accessibilityIdentifier("Tab.Journal")
                }
                .tag(AppTab.journal)

            TrendsView()
                .tabItem {
                    Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                        .accessibilityIdentifier("Tab.Trends")
                }
                .tag(AppTab.trends)
        }
        .marbleSessionAccessory(
            rest: restTimer.activeRest,
            session: activeSessions.first,
            onEndRest: {
                RestActivityController.shared.cancelRest()
            },
            onOpenSession: {
                showingActiveWorkout = true
            }
        )
        .environment(tabSelection)
        .environment(quickLog)
        .environment(\.logSetZoomNamespace, logSetZoom)
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
        .onReceive(NotificationCenter.default.publisher(for: .marbleOpenTextImport)) { _ in
            tabSelection.selected = .addWorkout
        }
        .onOpenURL { url in
            // Widget deep links (`marble://trends`, `marble://quicklog`).
            // Widget URLs are delivered straight to the owning app, so the
            // scheme needs no Info.plist registration — but we still check it
            // before acting on a host.
            guard url.scheme == "marble" else { return }
            // The medium widget's quick-log affordance lands on the same
            // coordinator the `.marbleOpenQuickLog` notification above does.
            if url.host == "quicklog" {
                quickLog.open()
                return
            }
            if url.host == "import" {
                tabSelection.selected = .addWorkout
                NotificationCenter.default.post(name: .marbleOpenTextImport, object: nil)
                return
            }
            if ["split", "train", "workout"].contains(url.host ?? "") {
                tabSelection.selected = .addWorkout
                showingActiveWorkout = !activeSessions.isEmpty
                return
            }
            guard let tab = Self.tab(for: url.host) else { return }
            tabSelection.selected = tab
        }
        .sheet(isPresented: rootQuickLogPresentation, onDismiss: {
            quickLog.clearPresentationContext()
        }) {
            AddSetView(
                initialPerformedAt: quickLog.prefillDate,
                initialExercise: fetchExercise(id: quickLog.prefillExerciseID),
                context: quickLog.context,
                // Fall back to the live session only for today's logging. The
                // Calendar's "Log Set for this day" opens this sheet with a
                // past prefill date and no session — appending that set to
                // today's active workout would pollute its set count and
                // sprint rep sequencing with a different day's training.
                activeSession: fetchWorkoutSession(id: quickLog.workoutSessionID)
                    ?? (Calendar.current.isDate(quickLog.prefillDate, inSameDayAs: AppEnvironment.now)
                        ? activeSessions.first
                        : nil),
                isPresented: rootQuickLogPresentation
            )
                .modelContext(modelContext)
                .environment(quickLog)
                .navigationTransition(.zoom(sourceID: "log-set", in: logSetZoom))
                .presentationDetents([.medium, .large], selection: Binding(
                    get: { quickLog.sheetDetent },
                    set: { quickLog.sheetDetent = $0 }
                ))
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.visible)
                .sheetGlassBackground()
        }
        .sheet(isPresented: $showingActiveWorkout) {
            WorkoutView()
                .modelContext(modelContext)
                .environment(quickLog)
                .environment(\.logSetZoomNamespace, logSetZoom)
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
            if TestHooks.isUITesting || TestHooks.seedDemoFixtures {
                if let tab = Self.tab(for: TestHooks.initialTab) {
                    tabSelection.selected = tab
                    if tab.isLogSection {
                        tabSelection.lastLogTab = tab
                    }
                } else if TestHooks.calendarTestDay != nil {
                    tabSelection.selectLogMode(.calendar)
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

    private var tabBarSelection: Binding<AppTab> {
        Binding(
            get: { tabSelection.tabBarSelection },
            set: { tabSelection.tabBarSelection = $0 }
        )
    }

    private static func tab(for identifier: String?) -> AppTab? {
        switch identifier {
        case "journal", "log":
            return .journal
        case "calendar":
            return .calendar
        case "add", "compose", "import", "split", "train", "workout":
            return .addWorkout
        case "supplements":
            return .supplements
        case "trends", "progress":
            return .trends
        default:
            return nil
        }
    }

    /// The active workout presents its own Add Set sheet from inside its sheet
    /// hierarchy. Keeping the root binding false while Workout is open avoids
    /// competing sibling sheet presentations in SwiftUI.
    private var rootQuickLogPresentation: Binding<Bool> {
        Binding(
            get: { quickLog.isPresentingAddSet && !showingActiveWorkout },
            set: { newValue in
                guard !showingActiveWorkout else { return }
                quickLog.isPresentingAddSet = newValue
            }
        )
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
