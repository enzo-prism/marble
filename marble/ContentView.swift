import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var quickLog = QuickLogCoordinator()
    @StateObject private var tabSelection = TabSelection()

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
        .environmentObject(tabSelection)
        .environmentObject(quickLog)
        .tabBarGlassBackground()
        .tint(Theme.primaryTextColor(for: colorScheme))
        .onAppear {
            Theme.applyTabBarAppearance(for: colorScheme)
        }
        .onChange(of: colorScheme) { scheme in
            Theme.applyTabBarAppearance(for: scheme)
        }
        .sheet(isPresented: $quickLog.isPresentingAddSet) {
            AddSetView(initialPerformedAt: quickLog.prefillDate, isPresented: $quickLog.isPresentingAddSet)
                .modelContext(modelContext)
                .environmentObject(quickLog)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .sheetGlassBackground()
        }
        .background(Theme.backgroundColor(for: colorScheme))
        .applyTestOverrides()
        .task {
            if TestHooks.isUITesting, TestHooks.calendarTestDay != nil {
                tabSelection.selected = .calendar
            }
        }
    }
}

#Preview {
    ContentView()
}
