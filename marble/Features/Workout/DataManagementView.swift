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
                    SectionHeaderView(title: "On This iPhone")
                }

                Section {
                    Button("Export Marble Backup", systemImage: "square.and.arrow.up", action: prepareExport)
                        .accessibilityIdentifier("Data.Export")
                    Button("Restore From Backup", systemImage: "square.and.arrow.down", action: { showingImporter = true })
                        .accessibilityIdentifier("Data.Restore")
                } header: {
                    SectionHeaderView(title: "Backup")
                } footer: {
                    Text("Backups contain exercises, sets, supplements, workout sessions, and your split. Progress photos and videos stay on this device.")
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
                Text("This adds missing data without deleting anything: \(pendingSummary.sets) sets, \(pendingSummary.sessions) sessions, and \(pendingSummary.supplementLogs) supplement logs.")
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
            statusMessage = "Restored \(summary.sets) sets and \(summary.sessions) sessions."
            clearPendingImport()
            MarbleHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
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
