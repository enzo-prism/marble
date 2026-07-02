import SwiftUI
import SwiftData

struct ImportView: View {
    @State private var viewModel: ImportViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var showingScan = false
    @State private var autoImportEnabled = HealthAutoImportService.shared.isEnabled
    @State private var detailSelection: DetailSelection?

    /// The five most recent ledger rows, shown as "Recently imported" so the
    /// hub reflects what's already in the journal, not just what's fetchable.
    @Query(sort: \ImportedWorkout.importedAt, order: .reverse)
    private var importHistory: [ImportedWorkout]

    private let autoImport = HealthAutoImportService.shared

    /// Identifiable wrapper so both fetched records and history rows can open
    /// the same detail sheet.
    private struct DetailSelection: Identifiable {
        let id = UUID()
        let details: ImportedWorkoutDetailView.Details
        /// Heart-rate series only makes sense for Apple Health workouts, where
        /// the window can be re-queried live.
        let loadsHeartRate: Bool
    }

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

                historySection

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
            .task {
                await viewModel.refreshStatus()
                await autoImport.syncIfEnabled(into: modelContext)
            }
            .sheet(isPresented: $showingScan) {
                WorkoutScanView()
                    .modelContext(modelContext)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .sheetGlassBackground()
            }
            .sheet(item: $detailSelection) { selection in
                NavigationStack {
                    ImportedWorkoutDetailView(
                        details: selection.details,
                        heartRateLoader: selection.loadsHeartRate ? heartRateLoader : nil
                    )
                    .navigationTitle("Workout")
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationBarGlassBackground()
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .sheetGlassBackground()
            }
        }
    }

    /// Live heart-rate loader for the detail sparkline; only wired for Apple
    /// Health workouts.
    private var heartRateLoader: (Date, Date) async -> [HeartRatePoint] {
        { start, end in
            guard let provider = viewModel.provider(for: .appleHealth) as? HealthKitWorkoutProvider else {
                return []
            }
            return await provider.heartRateSeries(start: start, end: end)
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
            if source == .appleHealth, case .authorized = state.status {
                autoImportRow
            }

            ForEach(state.records) { record in
                recordRow(record, source: source)
            }

            if shouldShowZeroResultsGuidance(source: source, state: state) {
                zeroResultsGuidance(source: source, state: state)
            }
        } header: {
            sourceHeader(source: source, state: state)
        }
    }

    /// HealthKit never reveals whether read access was granted or denied, so a
    /// zero-result load is the one moment to point at the Health privacy
    /// settings without accusing anyone.
    private func shouldShowZeroResultsGuidance(source: ImportSource, state: ImportViewModel.SourceState) -> Bool {
        source == .appleHealth
            && state.hasLoaded
            && state.records.isEmpty
            && !state.isFetching
            && state.errorMessage == nil
    }

    @ViewBuilder
    private func zeroResultsGuidance(source: ImportSource, state: ImportViewModel.SourceState) -> some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            Text(state.lastLookbackDays.map { "No workouts found in the last \($0) days." } ?? "No workouts found.")
                .font(MarbleTypography.rowSubtitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            Text("If you expected workouts here, try a longer range with Load, and check that Marble can read them: Settings › Apps › Health › Data Access & Devices › Marble. Garmin workouts appear after the Garmin Connect app syncs to Apple Health.")
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .marbleRowInsets()
        .listRowBackground(Theme.backgroundColor(for: colorScheme))
        .accessibilityIdentifier("Import.appleHealth.Empty")
    }

    /// Auto-import keeps the journal current without visiting this screen; the
    /// toggle lives with the Apple Health section because that's the source it
    /// syncs.
    private var autoImportRow: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
            Toggle("Auto-import new workouts", isOn: $autoImportEnabled)
                .font(MarbleTypography.rowTitle)
                .tint(Theme.dividerColor(for: colorScheme))
                .onChange(of: autoImportEnabled) { _, enabled in
                    autoImport.setEnabled(enabled)
                    MarbleHaptics.selection()
                }
                .accessibilityIdentifier("Import.AutoImport.Toggle")

            Text("Each time you open Marble, workouts recorded after you turned this on are added to your journal automatically.")
                .font(MarbleTypography.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            if let result = autoImport.lastResult {
                Text("Last auto-import: \(result.importedWorkouts) workout\(result.importedWorkouts == 1 ? "" : "s") on \(Formatters.day.string(from: result.date))")
                    .font(MarbleTypography.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .accessibilityIdentifier("Import.AutoImport.LastResult")
            }
        }
        .marbleRowInsets()
        .listRowBackground(Theme.backgroundColor(for: colorScheme))
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
                loadMenu(source: source, state: state)

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

    /// Load defaults to the last 30 days; the menu offers deeper lookbacks so a
    /// Garmin backlog or an old training block is one tap away.
    private func loadMenu(source: ImportSource, state: ImportViewModel.SourceState) -> some View {
        Menu {
            Button("Last 30 days") {
                Task { await viewModel.fetch(source, into: modelContext, lookbackDays: 30) }
            }
            Button("Last 90 days") {
                Task { await viewModel.fetch(source, into: modelContext, lookbackDays: 90) }
            }
            Button("Last year") {
                Task { await viewModel.fetch(source, into: modelContext, lookbackDays: 365) }
            }
        } label: {
            Label("Load", systemImage: "arrow.clockwise")
        } primaryAction: {
            Task { await viewModel.fetch(source, into: modelContext, lookbackDays: state.lastLookbackDays ?? 30) }
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("Import.\(source.rawValue).Fetch")
        .disabled(state.isFetching || viewModel.isImporting)
    }

    private func isConnectDisabled(_ status: ImportAuthorizationStatus) -> Bool {
        if case .needsConfiguration = status { return true }
        return false
    }

    @ViewBuilder
    private func recordRow(_ record: WorkoutImportRecord, source: ImportSource) -> some View {
        let selected = viewModel.selection.contains(record.id)
        let alreadyImported = (viewModel.states[source]?.alreadyImported.contains(record.externalID)) ?? false
        HStack(spacing: MarbleSpacing.s) {
            Button {
                if !alreadyImported {
                    viewModel.toggle(record)
                    MarbleHaptics.selection()
                }
            } label: {
                HStack(spacing: MarbleSpacing.s) {
                    Image(systemName: record.kind.systemImage)
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
                            .monospacedDigit()
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
            .accessibilityIdentifier("Import.\(source.rawValue).Row.\(record.externalID)")

            Button {
                detailSelection = DetailSelection(
                    details: ImportedWorkoutDetailView.Details(record: record),
                    loadsHeartRate: source == .appleHealth
                )
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .frame(minWidth: 32, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Workout details")
            .accessibilityIdentifier("Import.\(source.rawValue).Row.\(record.externalID).Detail")
        }
        .marbleRowInsets()
        .listRowBackground(
            selected
                ? Theme.chipFillColor(for: colorScheme)
                : Theme.backgroundColor(for: colorScheme)
        )
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
        let latestGarmin = viewModel.latestAppleHealthOriginDate("Garmin")
        Section {
            VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                // The section id lives on the header row, NOT the enclosing
                // VStack — a container identifier clobbers its children's
                // identifiers (the Open button below would vanish from the
                // accessibility tree; same trap as the old Import.Scan id).
                HStack(spacing: MarbleSpacing.s) {
                    Image(systemName: ImportSource.garminConnect.systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Garmin Connect")
                            .font(MarbleTypography.rowTitle)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        Text(garminCount > 0 ? "Bridged via Apple Health" : "Bridged via Apple Health — set up once")
                            .font(MarbleTypography.rowMeta)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                }
                .accessibilityIdentifier("Import.GarminBridge")

                if garminCount > 0 {
                    VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                        Label("\(garminCount) Garmin workout\(garminCount == 1 ? "" : "s") in the loaded range", systemImage: "checkmark.circle.fill")
                            .font(MarbleTypography.caption)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                            .accessibilityIdentifier("Import.GarminBridge.Found")
                        if let latestGarmin {
                            Text("Latest: \(Formatters.day.string(from: latestGarmin))")
                                .font(MarbleTypography.caption)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                        garminStep(number: 1, text: "In Garmin Connect, open More › Settings › Apple Health and turn syncing on.")
                        garminStep(number: 2, text: "Open Garmin Connect after a workout so it syncs to Apple Health.")
                        garminStep(number: 3, text: "Load Apple Health above — Garmin activities show a “Garmin” badge.")
                    }
                }

                Text("If a recent workout is missing, open Garmin Connect first — it writes to Apple Health when it syncs.")
                    .font(MarbleTypography.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open Garmin Connect") {
                    openGarminConnect()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("Import.GarminBridge.Open")
            }
            .marbleRowInsets()
            .listRowBackground(Theme.backgroundColor(for: colorScheme))
        }
    }

    private func garminStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: MarbleSpacing.xs) {
            Text("\(number).")
                .font(MarbleTypography.rowMeta)
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            Text(text)
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func openGarminConnect() {
        // Garmin Connect's registered scheme is the ConnectIQ one (gcm-ciq);
        // the legacy garminconnect:// is tried second, with the App Store page
        // as the always-works fallback.
        let schemeURL = URL(string: "gcm-ciq://")!
        let legacyURL = URL(string: "garminconnect://")!
        let storeURL = URL(string: "https://apps.apple.com/app/garmin-connect/id583446403")!
        openURL(schemeURL) { accepted in
            if accepted { return }
            openURL(legacyURL) { legacyAccepted in
                if !legacyAccepted { openURL(storeURL) }
            }
        }
    }

    /// What's already been imported, newest first, so the hub doubles as a
    /// receipt: each row opens the same detail screen as a fetched workout.
    @ViewBuilder
    private var historySection: some View {
        if !importHistory.isEmpty {
            Section {
                ForEach(importHistory.prefix(5)) { workout in
                    Button {
                        detailSelection = DetailSelection(
                            details: ImportedWorkoutDetailView.Details(workout: workout),
                            loadsHeartRate: workout.source == .appleHealth
                        )
                    } label: {
                        historyRow(workout)
                    }
                    .buttonStyle(.plain)
                    .marbleRowInsets()
                    .listRowBackground(Theme.backgroundColor(for: colorScheme))
                }
                if importHistory.count > 5 {
                    Text("and \(importHistory.count - 5) more in your journal")
                        .font(MarbleTypography.caption)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .marbleRowInsets()
                        .listRowBackground(Theme.backgroundColor(for: colorScheme))
                }
            } header: {
                SectionHeaderView(title: "Recently Imported")
            }
            .accessibilityIdentifier("Import.History")
        }
    }

    private func historyRow(_ workout: ImportedWorkout) -> some View {
        HStack(spacing: MarbleSpacing.s) {
            Image(systemName: (workout.kind ?? .other).systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: MarbleSpacing.xs) {
                    Text(workout.title)
                        .font(MarbleTypography.rowTitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    originBadge(workout.displayOrigin)
                }
                Text("\(Formatters.day.string(from: workout.workoutDate)) · \(workout.setsImported) set\(workout.setsImported == 1 ? "" : "s")")
                    .font(MarbleTypography.rowMeta)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
            Spacer(minLength: MarbleSpacing.xs)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func detailLine(for record: WorkoutImportRecord) -> String {
        var parts: [String] = [Formatters.day.string(from: record.date)]
        if let duration = record.durationSeconds, duration > 0 {
            parts.append(DateHelper.formattedDuration(seconds: duration))
        }
        if let distance = record.distanceMeters, distance > 0 {
            parts.append(ImportedWorkoutDetailView.distanceText(distance))
        }
        if let calories = record.calories, calories > 0 {
            parts.append("\(Int(calories)) kcal")
        }
        if let heartRate = record.averageHeartRate, heartRate > 0 {
            parts.append("\(Int(heartRate)) bpm")
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
