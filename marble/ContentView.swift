import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.undoManager) private var undoManager

    @State private var quickLog = QuickLogCoordinator()
    @State private var tabSelection = TabSelection()
    @State private var activeDay = DateHelper.startOfDay(for: AppEnvironment.now)

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

            SplitView()
                .tabItem {
                    Label("Split", systemImage: "list.bullet.clipboard")
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
                // A rest that expired while the app was suspended never ran its
                // auto-end task; clear it so the pill doesn't linger at 0:00.
                restTimer.pruneExpiredRest()
                // Pull any workouts that landed in Apple Health while we were
                // away (no-op unless the user enabled auto-import).
                Task { await HealthAutoImportService.shared.syncIfEnabled(into: modelContext) }
            }
            if newPhase == .active || newPhase == .background {
                // Keep the weekly-goal nudge honest: reschedule against what
                // was actually logged, cancel it once the target is hit.
                Task { await WeeklyGoalReminder.sync(modelContext: modelContext) }
                // Refresh Apple Health session export (no-op unless enabled).
                Task { await HealthSessionExporter.shared.exportIfEnabled(from: modelContext) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            refreshActiveDay()
        }
        .onReceive(NotificationCenter.default.publisher(for: .marbleOpenQuickLog)) { _ in
            quickLog.open()
        }
        .sheet(isPresented: $quickLog.isPresentingAddSet, onDismiss: {
            quickLog.clearPresentationContext()
        }) {
            AddSetView(
                initialPerformedAt: quickLog.prefillDate,
                initialExercise: fetchExercise(id: quickLog.prefillExerciseID),
                context: quickLog.context,
                isPresented: $quickLog.isPresentingAddSet
            )
                .modelContext(modelContext)
                .environment(quickLog)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .sheetGlassBackground()
        }
        .background(Theme.backgroundColor(for: colorScheme))
        .applyTestOverrides()
        .task {
            // Routes the system undo gestures (shake, three-finger swipe)
            // through SwiftData's change tracking.
            modelContext.undoManager = undoManager
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
}

#Preview {
    ContentView()
}
