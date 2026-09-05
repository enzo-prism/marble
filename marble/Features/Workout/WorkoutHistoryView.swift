import SwiftData
import SwiftUI
import os

struct WorkoutHistoryView: View {
    private let loadsHistory: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var search = ""
    @State private var filtersByDate = false
    @State private var selectedDate = AppEnvironment.now
    @State private var sessions: [WorkoutSession] = []
    @State private var hasMore = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    init() { loadsHistory = true }

    /// Deterministic presentation seam; production always fetches its own pages.
    init(snapshotSessions: [WorkoutSession]) {
        loadsHistory = false
        _sessions = State(initialValue: snapshotSessions)
        _isLoading = State(initialValue: false)
    }

    private var filter: Filter { Filter(search: search, day: filtersByDate ? selectedDate : nil) }
    private struct Filter: Equatable { let search: String; let day: Date? }

    var body: some View {
        List {
            if filtersByDate {
                DatePicker("Workout date", selection: $selectedDate, displayedComponents: .date)
                    .accessibilityIdentifier("History.Date")
                    .listRowBackground(Theme.backgroundColor(for: colorScheme))
            }
            if let errorMessage {
                ContentUnavailableView {
                    Label("Couldn't load workouts", systemImage: "exclamationmark.circle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") { loadPage(reset: true) }
                        .accessibilityIdentifier("History.Retry")
                }
            } else if sessions.isEmpty {
                if isLoading {
                    ProgressView("Loading workouts")
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title2)
                            .accessibilityHidden(true)
                        Text(search.isEmpty && !filtersByDate ? "No completed sessions" : "No matching sessions")
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(search.isEmpty && !filtersByDate
                            ? "Finished workouts and pasted or scanned sessions appear here. Health and Strava imports and individual sets stay in Log."
                            : "Try another exercise, workout name, or date.")
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowBackground(Theme.backgroundColor(for: colorScheme))
                    .listRowSeparator(.hidden)
                }
            }
            ForEach(sessions) { session in
                NavigationLink {
                    WorkoutSessionDetailView(session: session)
                } label: {
                    WorkoutSessionRow(session: session)
                }
                .accessibilityIdentifier("History.Session.\(session.id.uuidString)")
                .listRowBackground(Theme.backgroundColor(for: colorScheme))
                .marbleRowInsets()
            }
            if hasMore {
                Button("Load earlier workouts") { loadPage(reset: false) }
                    .frame(minHeight: 44)
                    .disabled(isLoading)
                    .accessibilityIdentifier("History.LoadMore")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
        .navigationTitle("Workout Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Workout or exercise")
        .searchToolbarBehavior(.minimize)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    filtersByDate.toggle()
                } label: {
                    Image(systemName: filtersByDate ? "calendar.badge.checkmark" : "calendar")
                }
                .accessibilityLabel(filtersByDate ? "Clear date filter" : "Filter by date")
                .accessibilityIdentifier("History.FilterDate")
            }
        }
        .task(id: filter) {
            guard loadsHistory else { return }
            isLoading = true
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard !Task.isCancelled else { return }
            loadPage(reset: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave, object: modelContext)) { _ in
            loadPage(reset: true)
        }
    }

    private func loadPage(reset: Bool) {
        let interval = HistoryPerformance.signposter.beginInterval("Workout history page")
        defer { HistoryPerformance.signposter.endInterval("Workout history page", interval) }
        do {
            let page = try modelContext.fetch(WorkoutHistoryQuery.descriptor(
                search: search, day: filtersByDate ? selectedDate : nil,
                offset: reset ? 0 : sessions.count
            ))
            hasMore = page.count > WorkoutHistoryQuery.pageSize
            let visible = Array(page.prefix(WorkoutHistoryQuery.pageSize))
            sessions = reset ? visible : sessions + visible
            errorMessage = nil
        } catch {
            errorMessage = "Your history is still saved. Try loading it again."
        }
        isLoading = false
    }
}

struct WorkoutSessionDetailView: View {
    let session: WorkoutSession
    private let loadsDetails: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var repeatDraft: RepeatPresentation?
    @State private var sprintDetails: [UUID: SprintRepDetail] = [:]
    @State private var showingPrecisionNotice = false
    @State private var detailLoadFailed = false
    @State private var detailsLoaded = false

    init(session: WorkoutSession) {
        self.session = session
        loadsDetails = true
    }

    init(snapshotSession: WorkoutSession) {
        session = snapshotSession
        loadsDetails = false
        _detailsLoaded = State(initialValue: true)
    }

    private struct RepeatPresentation: Identifiable {
        let id = UUID()
        let draft: ParsedWorkoutDraft
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.startedAt, format: .dateTime.weekday(.wide).month(.wide).day().year())
                        .font(.headline)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(session.entries.count) sets · \(DateHelper.formattedDuration(seconds: Int(session.duration)))")
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                    if let notes = session.notes, !notes.isEmpty {
                        Text(notes)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .listRowSeparator(.hidden)
                Button {
                    if sprintDetails.isEmpty {
                        repeatDraft = RepeatPresentation(draft: WorkoutRepeatDraft.make(from: session))
                    } else {
                        showingPrecisionNotice = true
                    }
                } label: {
                    Text("Repeat Workout")
                        .font(.headline)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primaryTextColor(for: colorScheme))
                .foregroundStyle(Theme.backgroundColor(for: colorScheme))
                .disabled(session.entries.isEmpty || detailLoadFailed || !detailsLoaded)
                .accessibilityHint("Review and edit a copy for today before saving")
                .accessibilityIdentifier("History.Repeat")
                if detailLoadFailed {
                    Text("Couldn't load precise sprint times. Reopen this workout to try again.")
                        .font(MarbleTypography.rowSubtitle)
                }
            }
            .listRowBackground(Theme.backgroundColor(for: colorScheme))
            Section {
                ForEach(WorkoutHistoryQuery.orderedEntries(for: session)) { entry in
                    NavigationLink {
                        SetDetailView(entry: entry)
                    } label: {
                        SetRowView(entry: entry, sprintDetail: sprintDetails[entry.id], accessibilityIdentifier: "History.SetLabel.\(entry.id.uuidString)")
                    }
                    .accessibilityIdentifier("History.Set.\(entry.id.uuidString)")
                    .listRowBackground(Theme.backgroundColor(for: colorScheme))
                    .marbleRowInsets()
                }
            } header: {
                Text("Sets")
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard loadsDetails else { return }
            let ids = session.entries.map(\.id)
            do {
                let details = try modelContext.fetch(FetchDescriptor<SprintRepDetail>(
                    predicate: #Predicate { ids.contains($0.setEntryID) }
                ))
                sprintDetails = Dictionary(details.map { ($0.setEntryID, $0) }, uniquingKeysWith: { first, _ in first })
                detailLoadFailed = false
                detailsLoaded = true
            } catch {
                detailLoadFailed = true
            }
        }
        .confirmationDialog("Repeat with whole-second times?", isPresented: $showingPrecisionNotice, titleVisibility: .visible) {
            Button("Review Whole-Second Copy") {
                repeatDraft = RepeatPresentation(draft: WorkoutRepeatDraft.make(from: session, sprintDetails: sprintDetails))
            }
            .accessibilityIdentifier("History.RepeatWholeSeconds")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("History.RepeatPrecisionCancel")
        } message: {
            Text("This workout has sprint times measured in tenths. The copy uses rounded whole seconds, with exact previous times and targets kept in its notes. Your original times and targets stay saved.")
        }
        .sheet(item: $repeatDraft) { presentation in
            WorkoutTextEntryView(initialReviewDraft: presentation.draft)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}
