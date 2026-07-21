import SwiftData
import SwiftUI

/// The single place Marble's preferences live.
///
/// Before 2.2 these were scattered: the weekly target was implicit in Trends,
/// the reminder toggle only existed inside Notifications, and both Apple Health
/// switches were buried in the import hub. This screen consolidates them without
/// forking their state — every control here drives the same key or service the
/// original screen drives, so the two surfaces can never disagree.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(SharedDefaults.Key.preferredWeightUnit, store: SharedDefaults.suite)
    private var preferredWeightUnitRaw = WeightUnit.lb.rawValue

    @AppStorage(SharedDefaults.Key.weeklySessionTarget, store: SharedDefaults.suite)
    private var weeklyTarget = TrainingConsistency.defaultWeeklyTarget

    @AppStorage(SharedDefaults.Key.weeklyGoalReminderEnabled, store: SharedDefaults.suite)
    private var weeklyGoalReminderEnabled = true

    // Health state mirrors the import hub exactly: the service owns the truth,
    // these are just the view's copy of it.
    @State private var autoImportEnabled = HealthAutoImportService.shared.isEnabled
    @State private var healthExportEnabled = UserDefaults.standard.bool(forKey: HealthSessionExporter.enabledDefaultsKey)
    @State private var showingData = false

    private let autoImport = HealthAutoImportService.shared

    private static let weeklyTargetRange = 2...6

    private var weightUnit: WeightUnit {
        WeightUnit(rawValue: preferredWeightUnitRaw) ?? .lb
    }

    var body: some View {
        NavigationStack {
            List {
                unitsSection
                trainingSection
                notificationsSection
                healthSection
                dataSection
                aboutSection
            }
            .listStyle(.plain)
            .listRowSeparatorTint(Theme.subtleDividerColor(for: colorScheme))
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundColor(for: colorScheme))
            .accessibilityIdentifier("Settings.List")
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                        .accessibilityIdentifier("Settings.Done")
                }
            }
        }
        .sheet(isPresented: $showingData) {
            // Data & Backups brings its own NavigationStack and Done button, so
            // it is presented rather than pushed.
            DataManagementView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .sheetGlassBackground()
        }
    }

    // MARK: - Units

    private var unitsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                Picker("Default weight unit", selection: Binding(
                    get: { weightUnit },
                    set: { newValue in
                        guard newValue != weightUnit else { return }
                        preferredWeightUnitRaw = newValue.rawValue
                        MarbleHaptics.selection()
                    }
                )) {
                    ForEach(WeightUnit.allCases) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .tint(Theme.dividerColor(for: colorScheme))
                .frame(minHeight: 44)
                .accessibilityLabel("Default weight unit")
                .accessibilityIdentifier("Settings.WeightUnit")

                Text("New sets start in this unit. Each set keeps its own unit, so you can still switch a single set without touching your history.")
                    .font(MarbleTypography.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .marbleRowInsets()
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.backgroundColor(for: colorScheme))
        } header: {
            SectionHeaderView(title: "Units")
        }
    }

    // MARK: - Training

    private var trainingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                Stepper(
                    value: $weeklyTarget,
                    in: Self.weeklyTargetRange,
                    step: 1
                ) {
                    HStack {
                        Text("Weekly sessions")
                            .font(MarbleTypography.rowTitle)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: MarbleSpacing.s)
                        Text("\(weeklyTarget)")
                            .font(MarbleTypography.rowSubtitle)
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }
                }
                .onChange(of: weeklyTarget) { _, _ in
                    MarbleHaptics.selection()
                }
                .frame(minHeight: 44)
                .accessibilityLabel("Weekly session goal")
                .accessibilityValue("\(weeklyTarget) sessions per week")
                .accessibilityIdentifier("Settings.WeeklyTarget")

                Text("Trends measures your consistency against this number.")
                    .font(MarbleTypography.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .marbleRowInsets()
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.backgroundColor(for: colorScheme))
        } header: {
            SectionHeaderView(title: "Training")
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                Toggle("Weekly goal reminder", isOn: $weeklyGoalReminderEnabled)
                    .font(MarbleTypography.rowTitle)
                    .tint(Theme.dividerColor(for: colorScheme))
                    .onChange(of: weeklyGoalReminderEnabled) { _, enabled in
                        MarbleHaptics.selection()
                        if !enabled {
                            WeeklyGoalReminder.removePending()
                        }
                    }
                    .accessibilityIdentifier("Settings.WeeklyGoalReminder")

                Text("A single quiet nudge on the last realistic evening to keep your weekly goal — cancelled automatically once you've trained.")
                    .font(MarbleTypography.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .marbleRowInsets()
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.backgroundColor(for: colorScheme))

            NavigationLink {
                NotificationsView(scheduler: CustomNotificationScheduler.live())
            } label: {
                Label("Custom Reminders", systemImage: "bell")
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .marbleRowInsets()
            .listRowBackground(Theme.backgroundColor(for: colorScheme))
            .accessibilityIdentifier("Settings.Notifications")
        } header: {
            SectionHeaderView(title: "Notifications")
        }
    }

    // MARK: - Apple Health

    private var healthSection: some View {
        Section {
            VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                Toggle("Auto-import new workouts", isOn: $autoImportEnabled)
                    .font(MarbleTypography.rowTitle)
                    .tint(Theme.dividerColor(for: colorScheme))
                    .onChange(of: autoImportEnabled) { _, enabled in
                        autoImport.setEnabled(enabled)
                        MarbleHaptics.selection()
                    }
                    .accessibilityIdentifier("Settings.HealthAutoImport")

                Text("Each time you open Marble, workouts recorded after you turned this on are added to your journal automatically.")
                    .font(MarbleTypography.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .marbleRowInsets()
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.backgroundColor(for: colorScheme))

            VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                Toggle("Send sessions to Apple Health", isOn: $healthExportEnabled)
                    .font(MarbleTypography.rowTitle)
                    .tint(Theme.dividerColor(for: colorScheme))
                    .onChange(of: healthExportEnabled) { _, enabled in
                        // Same flow as the import hub: persist first, then ask
                        // for write access and roll the toggle back if denied.
                        MarbleHaptics.selection()
                        UserDefaults.standard.set(enabled, forKey: HealthSessionExporter.enabledDefaultsKey)
                        guard enabled else { return }
                        Task {
                            let granted = await HealthSessionExporter.shared.requestAuthorization()
                            if granted {
                                await HealthSessionExporter.shared.exportIfEnabled(from: modelContext)
                            } else {
                                healthExportEnabled = false
                                UserDefaults.standard.set(false, forKey: HealthSessionExporter.enabledDefaultsKey)
                            }
                        }
                    }
                    .accessibilityIdentifier("Settings.HealthExport")

                Text("Completed training days are saved to Apple Health as strength workouts with your session effort (RPE), so Marble sessions count toward Apple's Training Load.")
                    .font(MarbleTypography.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .marbleRowInsets()
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.backgroundColor(for: colorScheme))
        } header: {
            SectionHeaderView(title: "Apple Health")
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        Section {
            Button {
                showingData = true
            } label: {
                HStack {
                    Label("Data & Backups", systemImage: "externaldrive")
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: MarbleSpacing.s)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            .frame(minHeight: 44)
            .marbleRowInsets()
            .listRowBackground(Theme.backgroundColor(for: colorScheme))
            .accessibilityIdentifier("Settings.Data")
        } header: {
            SectionHeaderView(title: "Data")
        } footer: {
            Text("Export a backup, restore one, and manage your exercise library.")
                .font(MarbleTypography.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: MarbleSpacing.s) {
                Text("Marble stores everything on your device. No account, no server, no tracking.")
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text("Version")
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: MarbleSpacing.s)
                    Text(Self.versionText)
                        .font(MarbleTypography.rowMeta)
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("Settings.Version")
            }
            .marbleRowInsets()
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.backgroundColor(for: colorScheme))
        } header: {
            SectionHeaderView(title: "About")
        }
    }

    /// "2.2 (41)" — falls back gracefully because this project generates its
    /// Info.plist and the keys can be absent in some test hosts.
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String
        guard let build, !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
}
