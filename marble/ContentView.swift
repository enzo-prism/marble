import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var quickLog = QuickLogCoordinator()

    @Query(sort: \SetEntry.performedAt, order: .reverse)
    private var recentSets: [SetEntry]

    var body: some View {
        TabView {
            JournalView()
                .tabItem {
                    Label("Journal", systemImage: "list.bullet.rectangle")
                }

            CalendarView()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }

            SupplementsView()
                .tabItem {
                    Label("Supplements", systemImage: "pills")
                }

            TrendsView()
                .tabItem {
                    Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
                }
        }
        .environmentObject(quickLog)
        .quickLogAccessory(isPresented: $quickLog.isPresentingAddSet, hint: quickLogHint)
        .tabBarGlassBackground()
        .tint(Theme.primaryTextColor(for: colorScheme))
        .sheet(isPresented: $quickLog.isPresentingAddSet) {
            AddSetView(initialPerformedAt: quickLog.prefillDate)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .sheetGlassBackground()
        }
        .background(Theme.backgroundColor(for: colorScheme))
        .task {
            SeedData.seedIfNeeded(in: modelContext)
        }
    }

    private var quickLogHint: String? {
        recentSets.first?.exercise.name
    }
}

#Preview {
    ContentView()
}
