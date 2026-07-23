import AppIntents
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct DataManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query private var exercises: [Exercise]
    @Query private var entries: [SetEntry]
    @Query private var supplementEntries: [SupplementEntry]
    @Query private var sessions: [WorkoutSession]

    @State private var exportDocument: MarbleBackupDocument?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var pendingImportData: Data?
    @State private var pendingSummary: MarbleBackupSummary?
    @State private var showingRestoreConfirmation = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if PersistenceRecoveryNotice.needsAttention {
                    recoverySection
                }

                Section {
                    dataSummary
                } header: {
                    SectionHeaderView(title: "On This Device")
                }

                Section {
                    NavigationLink {
                        ManageExercisesView()
                    } label: {
                        Label("Exercise Library", systemImage: "figure.strengthtraining.traditional")
                    }
                    .accessibilityIdentifier("Data.ExerciseLibrary")
                } header: {
                    SectionHeaderView(title: "Library")
                } footer: {
                    Text("Create, search, and safely edit the exercises you use throughout Marble.")
                }

                Section {
                    Button("Export Marble Backup", systemImage: "square.and.arrow.up", action: prepareExport)
                        .accessibilityIdentifier("Data.Export")
                    Button("Restore From Backup", systemImage: "square.and.arrow.down", action: { showingImporter = true })
                        .accessibilityIdentifier("Data.Restore")
                } header: {
                    SectionHeaderView(title: "Backup")
                } footer: {
                    Text("Backups contain exercises, sets, supplements, workout sessions, weigh-ins, and your split. Progress photos and videos stay on this device.")
                }

                if let statusMessage {
                    Section {
                        Label(statusMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundColor(for: colorScheme))
            .navigationTitle("Data & Backups")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                        .accessibilityIdentifier("Data.Done")
                }
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Marble-Backup-\(Self.filenameDate.string(from: AppEnvironment.now))"
        ) { result in
            switch result {
            case .success:
                statusMessage = "Backup exported successfully."
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            handleImportSelection(result)
        }
        .confirmationDialog("Restore this backup?", isPresented: $showingRestoreConfirmation) {
            Button("Restore and Merge") { restorePendingBackup() }
                .accessibilityIdentifier("Data.Restore.Confirm")
            Button("Cancel", role: .cancel) { clearPendingImport() }
                .accessibilityIdentifier("Data.Restore.Cancel")
        } message: {
            if let pendingSummary {
                // Weigh-ins are called out explicitly: they used to be dropped
                // entirely, and a count is the only way the user can tell
                // whether their bodyweight history came back.
                Text("This adds missing data without deleting anything: \(pendingSummary.sets) sets, \(pendingSummary.sessions) sessions, \(pendingSummary.supplementLogs) supplement logs, and \(pendingSummary.bodyMetrics) weigh-ins.")
            }
        }
        .alert("Data Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
                .accessibilityIdentifier("Data.Error.OK")
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var recoverySection: some View {
        Section {
            VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                Label("Marble recovered its database", systemImage: "externaldrive.badge.exclamationmark")
                    .font(MarbleTypography.rowTitle)
                Text("The unreadable store was preserved on this iPhone and Marble opened a fresh database. Export your current data and contact support before removing the app.")
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                Button("I Understand") {
                    PersistenceRecoveryNotice.acknowledge()
                    statusMessage = "Recovery notice acknowledged."
                }
                .buttonStyle(MarbleActionButtonStyle(prominence: .primary))
                .accessibilityIdentifier("Data.RecoveryAcknowledge")
            }
            .padding(.vertical, MarbleSpacing.s)
        }
    }

    private var dataSummary: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            summaryRow("Exercises", value: exercises.count)
            summaryRow("Sets", value: entries.count)
            summaryRow("Workout sessions", value: sessions.count)
            summaryRow("Supplement logs", value: supplementEntries.count)
        }
        .padding(.vertical, MarbleSpacing.s)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("Data.Summary")
    }

    private func summaryRow(_ title: String, value: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(value)")
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .monospacedDigit()
        }
    }

    private func prepareExport() {
        do {
            exportDocument = try MarbleBackupService.makeDocument(in: modelContext)
            showingExporter = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleImportSelection(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            pendingImportData = data
            pendingSummary = try MarbleBackupService.inspect(data: data)
            showingRestoreConfirmation = true
        } catch {
            clearPendingImport()
            errorMessage = error.localizedDescription
        }
    }

    private func restorePendingBackup() {
        guard let pendingImportData else { return }
        do {
            let summary = try MarbleBackupService.restore(data: pendingImportData, into: modelContext)
            statusMessage = "Restored \(summary.sets) sets, \(summary.sessions) sessions, and \(summary.bodyMetrics) weigh-ins."
            clearPendingImport()
            MarbleHaptics.success()
            // A restore rewrites weeks of history without a scene-phase
            // change, so every surface ContentView refreshes on background
            // would keep describing the pre-restore store: the Weekly Goal
            // widget (the shipped "restore doesn't refresh the widget"
            // defect), the at-risk nudge, Spotlight's exercise rows, and the
            // parameterised "Log a set of <exercise>" phrases for any
            // exercises the backup brought in. The refresh lives here rather
            // than in `MarbleBackupService` so the service stays a pure store
            // operation `MarbleBackupTests` can exercise without ambient
            // system side effects — the same split as ContentView owning the
            // scene-phase publish.
            WeeklyGoalWidgetPublisher.publish(modelContext: modelContext)
            Task { await WeeklyGoalReminder.sync(modelContext: modelContext) }
            Task { await ExerciseSpotlightIndex.reindexAll() }
            MarbleShortcuts.updateAppShortcutParameters()
            rescheduleNotificationsAfterRestore()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Restored `CustomNotification` rows exist only in the store — nothing
    /// has told UNUserNotificationCenter about them, so without this pass a
    /// restored reminder would sit silently in the list and never fire.
    /// Re-syncs every enabled reminder the same way
    /// `NotificationsView.requestPermission` does. `sync` is idempotent (it
    /// removes the row's pending requests before re-adding), so rows that
    /// existed before the restore are simply refreshed, and
    /// `CustomNotificationScheduler.live()` already routes UI tests to the
    /// no-op client via `TestHooks`. If permission is undetermined, `sync`
    /// asks — the user just chose to restore their reminders, so the prompt
    /// is expected, and a denial leaves the rows intact for later. Lives here
    /// rather than in `MarbleBackupService` for the same reason as the widget
    /// publish above: the service stays a pure store operation.
    private func rescheduleNotificationsAfterRestore() {
        let scheduler = CustomNotificationScheduler.live()
        Task {
            let notifications = (try? modelContext.fetch(FetchDescriptor<CustomNotification>())) ?? []
            for notification in notifications where notification.isEnabled {
                _ = await scheduler.sync(notification)
            }
        }
    }

    private func clearPendingImport() {
        pendingImportData = nil
        pendingSummary = nil
    }

    private static let filenameDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
