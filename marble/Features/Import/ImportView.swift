import SwiftUI
import SwiftData

struct ImportView: View {
    @State private var viewModel: ImportViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var showingScan = false

    init(viewModel: ImportViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                scanSection

                ForEach(viewModel.sources, id: \.self) { source in
                    sourceSection(for: source)
                }

                garminBridgeSection

                if let message = viewModel.importErrorMessage {
                    Section {
                        Text(message)
                            .font(MarbleTypography.rowMeta)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                            .marbleRowInsets()
                            .listRowBackground(Theme.backgroundColor(for: colorScheme))
                            .accessibilityIdentifier("Import.Error")
                    }
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
            .sheet(isPresented: $showingScan) {
                WorkoutScanView()
                    .modelContext(modelContext)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .sheetGlassBackground()
            }
        }
    }

    /// Entry point for the on-device handwritten-workout scanner. It has no remote
    /// service, so it lives outside the provider list and opens its own review flow.
    private var scanSection: some View {
        Section {
            VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                HStack(spacing: MarbleSpacing.s) {
                    Image(systemName: ImportSource.photoScan.systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    Text(ImportSource.photoScan.displayName)
                        .font(MarbleTypography.rowTitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                }

                Text("Snap a photo of a handwritten workout. Marble reads it on your device and turns it into sets you can review before logging.")
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                Button("Scan a Workout") { showingScan = true }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("Import.Scan.Open")
            }
            .marbleRowInsets()
            .listRowBackground(Theme.backgroundColor(for: colorScheme))
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
    private func statusLabel(for status: ImportAuthorizationStatus) -> some View {
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
    private func actionButton(source: ImportSource, state: ImportViewModel.SourceState) -> some View {
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
                .disabled(state.isFetching || viewModel.isImporting)

                if source == .strava {
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
                    HStack(spacing: MarbleSpacing.xs) {
                        Text(record.title)
                            .font(MarbleTypography.rowTitle)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        if let origin = record.originName, source == .appleHealth {
                            originBadge(origin)
                        }
                    }
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
                        .contentTransition(.symbolEffect(.replace))
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

    @ViewBuilder
    private func originBadge(_ origin: String) -> some View {
        Text(origin)
            .font(MarbleTypography.caption)
            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            .padding(.horizontal, MarbleSpacing.xs)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(Theme.chipFillColor(for: colorScheme))
            )
            .accessibilityLabel("from \(origin)")
    }

    /// Garmin's ToS-aligned path into Marble is Apple Health, so we guide users there
    /// rather than handling Garmin credentials directly.
    @ViewBuilder
    private var garminBridgeSection: some View {
        let garminCount = viewModel.appleHealthOriginCount("Garmin")
        Section {
            VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                HStack(spacing: MarbleSpacing.s) {
                    Image(systemName: ImportSource.garminConnect.systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    Text("Garmin Connect")
                        .font(MarbleTypography.rowTitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                }

                Text("Garmin workouts come into Marble through Apple Health. In the Garmin Connect app, turn on Settings → Apple Health, then load your Apple Health workouts above — Garmin activities show a “Garmin” badge.")
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                if garminCount > 0 {
                    Label("Found \(garminCount) Garmin workout\(garminCount == 1 ? "" : "s") in Apple Health", systemImage: "checkmark.circle.fill")
                        .font(MarbleTypography.caption)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .accessibilityIdentifier("Import.GarminBridge.Found")
                }

                Button("Open Garmin Connect") {
                    openGarminConnect()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("Import.GarminBridge.Open")
            }
            .marbleRowInsets()
            .listRowBackground(Theme.backgroundColor(for: colorScheme))
            .accessibilityIdentifier("Import.GarminBridge")
        }
    }

    private func openGarminConnect() {
        // The Garmin Connect app's URL scheme, falling back to its App Store page so the
        // button always does something useful.
        let appURL = URL(string: "garminconnect://")!
        let storeURL = URL(string: "https://apps.apple.com/app/garmin-connect/id583446403")!
        openURL(appURL) { accepted in
            if !accepted { openURL(storeURL) }
        }
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
        // Apple Health is always available and is the sanctioned bridge for Apple Watch,
        // Garmin, and other devices that sync to HealthKit.
        var providers: [WorkoutImportProvider] = [HealthKitWorkoutProvider()]

        // Strava is a direct, official OAuth connector. It appears only once a developer
        // has wired up their own Strava API credentials in the Info.plist; otherwise we
        // hide a row that could never connect.
        let stravaConfiguration = StravaConfiguration.resolved
        if stravaConfiguration.isConfigured {
            providers.append(
                StravaProvider(client: StravaClient(configuration: stravaConfiguration))
            )
        }

        return ImportView(viewModel: ImportViewModel(providers: providers))
    }
}
