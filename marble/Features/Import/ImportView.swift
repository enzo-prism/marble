import SwiftUI
import SwiftData

struct ImportView: View {
    @StateObject private var viewModel: ImportViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    init(viewModel: ImportViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.sources, id: \.self) { source in
                    sourceSection(for: source)
                }

                if let summary = viewModel.lastSummary {
                    Section {
                        summaryRow(summary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundColor(for: colorScheme))
            .navigationTitle("Import Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("Import.Done")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.importSelected(into: modelContext) }
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("Import.Confirm")
                    .disabled(viewModel.selection.isEmpty || viewModel.isImporting)
                }
            }
            .task { await viewModel.refreshStatus() }
        }
    }

    @ViewBuilder
    private func sourceSection(for source: ImportSource) -> some View {
        let state = viewModel.states[source] ?? .init()
        Section {
            ForEach(state.records) { record in
                recordRow(record, source: source)
            }
        } header: {
            sourceHeader(source: source, state: state)
        }
    }

    @ViewBuilder
    private func sourceHeader(source: ImportSource, state: ImportViewModel.SourceState) -> some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            HStack(spacing: MarbleSpacing.s) {
                Image(systemName: source.systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.displayName)
                        .font(MarbleTypography.rowTitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    statusLabel(for: state.status)
                }
                Spacer()
                actionButton(source: source, state: state)
            }

            if state.isFetching {
                ProgressView()
                    .accessibilityIdentifier("Import.\(source.rawValue).Loading")
            }
            if let message = state.errorMessage {
                Text(message)
                    .font(MarbleTypography.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
        }
        .padding(.vertical, MarbleSpacing.xxs)
    }

    @ViewBuilder
    private func statusLabel(for status: ImportAuthorizationStatus) {
        switch status {
        case .authorized:
            Text("Connected").font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        case .notDetermined:
            Text("Not connected").font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        case .denied:
            Text("Access denied").font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        case .needsConfiguration(let message):
            Text(message ?? "Needs configuration").font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        }
    }

    @ViewBuilder
    private func actionButton(source: ImportSource, state: ImportViewModel.SourceState) {
        switch state.status {
        case .authorized:
            HStack(spacing: MarbleSpacing.xs) {
                Button {
                    Task { await viewModel.fetch(source, into: modelContext) }
                } label: {
                    Label("Load", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("Import.\(source.rawValue).Fetch")

                if source == .garminConnect {
                    Button("Disconnect") {
                        Task { await viewModel.disconnect(source) }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("Import.\(source.rawValue).Disconnect")
                }
            }
        case .denied, .notDetermined, .needsConfiguration:
            Button("Connect") {
                Task { await viewModel.connect(source) }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("Import.\(source.rawValue).Connect")
            .disabled(isConnectDisabled(state.status))
        }
    }

    private func isConnectDisabled(_ status: ImportAuthorizationStatus) -> Bool {
        if case .needsConfiguration = status { return true }
        return false
    }

    @ViewBuilder
    private func recordRow(_ record: WorkoutImportRecord, source: ImportSource) -> some View {
        let selected = viewModel.selection.contains(record.id)
        let alreadyImported = (viewModel.states[source]?.alreadyImported.contains(record.externalID)) ?? false
        Button {
            if !alreadyImported { viewModel.toggle(record) }
        } label: {
            HStack(spacing: MarbleSpacing.s) {
                Image(systemName: record.isStrength ? "dumbbell.fill" : "figure.run")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(record.title)
                        .font(MarbleTypography.rowTitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    Text(detailLine(for: record))
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }

                Spacer()

                if alreadyImported {
                    Label("Imported", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .accessibilityIdentifier("Import.\(source.rawValue).Row.\(record.externalID).Imported")
                } else {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Theme.primaryTextColor(for: colorScheme) : Theme.secondaryTextColor(for: colorScheme))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .marbleRowInsets()
        .listRowBackground(
            selected
                ? Theme.chipFillColor(for: colorScheme)
                : Theme.backgroundColor(for: colorScheme)
        )
        .accessibilityIdentifier("Import.\(source.rawValue).Row.\(record.externalID)")
    }

    private func detailLine(for record: WorkoutImportRecord) -> String {
        var parts: [String] = [Formatters.day.string(from: record.date)]
        if let distance = record.distanceMeters, distance > 0 {
            parts.append(Self.distanceText(distance))
        }
        if let duration = record.durationSeconds, duration > 0 {
            parts.append(Self.durationText(duration))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func summaryRow(_ summary: WorkoutImporter.Summary) -> some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
            Text("Imported \(summary.importedSets) set\(summary.importedSets == 1 ? "" : "s") from \(summary.importedWorkouts) workout\(summary.importedWorkouts == 1 ? "" : "s")")
                .font(MarbleTypography.rowTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            if summary.skipped > 0 {
                Text("\(summary.skipped) already imported")
                    .font(MarbleTypography.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
        }
        .marbleRowInsets()
        .listRowBackground(Theme.backgroundColor(for: colorScheme))
        .accessibilityIdentifier("Import.Summary")
    }

    private static func distanceText(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        }
        return "\(Int(meters)) m"
    }

    private static func durationText(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

extension ImportView {
    static func `default`() -> ImportView {
        let providers: [WorkoutImportProvider] = [
            HealthKitWorkoutProvider(),
            GarminConnectProvider(client: GarminConnectClient(configuration: .placeholder))
        ]
        return ImportView(viewModel: ImportViewModel(providers: providers))
    }
}
