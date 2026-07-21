import SwiftUI
import SwiftData

/// User preferences behind the body-metrics feature that have no home in the
/// SwiftData store (they describe how to *score*, not what was measured).
///
/// Kept in `.standard` with a `marble.body.` prefix, matching the
/// `marble.health.` keys `HealthAutoImportService` and
/// `BodyMetricsAutoImportService` already use.
enum BodyMetricsPreferences {
    /// DOTS is defined with sex-specific polynomial coefficients; there is no
    /// unisex variant, so relative strength cannot be scored without this.
    /// Defaults to false (men's coefficients) purely because it must default to
    /// something — the entry sheet exposes it, and Settings should too.
    static let dotsUsesFemaleCoefficientsKey = "marble.body.dotsUsesFemaleCoefficients"
}

/// Quick weight entry: log today's bodyweight in whichever unit the lifter
/// prefers, stored as canonical kilograms.
///
/// The unit shown here is `SharedDefaults.Key.preferredWeightUnit` — the same
/// key Settings, Onboarding, and `AddSetView` read. The conversion to kilograms
/// happens exactly once, in `save()`, through
/// `BodyMetricEntry.canonicalKilograms(from:unit:)`. Nothing downstream ever
/// sees a pound value.
///
/// Embeds its own `NavigationStack` so it drops straight into a `.sheet { }`.
struct BodyMetricEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// Existing measurement to edit; nil logs a new one.
    let entry: BodyMetricEntry?

    init(entry: BodyMetricEntry? = nil) {
        self.entry = entry
    }

    @AppStorage(SharedDefaults.Key.preferredWeightUnit, store: SharedDefaults.suite)
    private var preferredWeightUnitRaw = WeightUnit.lb.rawValue

    @AppStorage(BodyMetricsPreferences.dotsUsesFemaleCoefficientsKey)
    private var dotsUsesFemaleCoefficients = false

    @State private var weight: Double?
    @State private var bodyFatPercent: Double?
    @State private var measuredAt = AppEnvironment.now
    @State private var notes = ""
    /// Seeded from the preferred unit, then local to this sheet: switching it
    /// here converts the entry, it does not silently rewrite the app-wide
    /// preference.
    @State private var unit: WeightUnit = .lb
    @State private var didLoad = false

    private var preferredWeightUnit: WeightUnit {
        WeightUnit(rawValue: preferredWeightUnitRaw) ?? .lb
    }

    /// Kilograms the current input would save as, when it is valid at all.
    private var canonicalKilograms: Double? {
        guard let weight, weight > 0 else { return nil }
        let kilograms = BodyMetricEntry.canonicalKilograms(from: weight, unit: unit)
        return BodyMetricEntry.isPlausible(kilograms: kilograms) ? kilograms : nil
    }

    private var canSave: Bool { canonicalKilograms != nil }

    var body: some View {
        NavigationStack {
            List {
                weightSection
                detailSection
                scoringSection
            }
            .listStyle(.plain)
            .listRowSeparatorTint(Theme.dividerColor(for: colorScheme))
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundColor(for: colorScheme))
            .navigationTitle(entry == nil ? "Log Weight" : "Edit Weight")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
            .marbleKeyboardToolbar(
                primaryAction: KeyboardToolbarAction(
                    title: "Save",
                    accessibilityIdentifier: "Keyboard.Save",
                    isEnabled: canSave,
                    handler: save
                )
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("BodyMetricEntry.Cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .accessibilityIdentifier("BodyMetricEntry.Save")
                }
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    // MARK: - Sections

    private var weightSection: some View {
        Section {
            HStack(spacing: MarbleSpacing.s) {
                OptionalNumberField(
                    title: "Weight",
                    formatter: Formatters.weight,
                    value: $weight,
                    accessibilityIdentifier: "BodyMetricEntry.Weight"
                )

                Picker("Unit", selection: $unit) {
                    ForEach(WeightUnit.allCases) { unit in
                        Text(unit.symbol.uppercased()).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 116)
                .accessibilityIdentifier("BodyMetricEntry.Unit")
            }

            DatePicker(
                "Measured",
                selection: $measuredAt,
                in: ...AppEnvironment.now,
                displayedComponents: [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("BodyMetricEntry.MeasuredAt")
        } footer: {
            Text("Stored in kilograms and shown back in your preferred unit, so switching units never changes your history.")
                .font(MarbleTypography.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var detailSection: some View {
        Section {
            OptionalNumberField(
                title: "Body Fat %",
                formatter: Formatters.weight,
                value: $bodyFatPercent,
                accessibilityIdentifier: "BodyMetricEntry.BodyFat"
            )

            TextField("Notes", text: $notes, axis: .vertical)
                .marbleFieldStyle()
                .lineLimit(1...4)
                .accessibilityIdentifier("BodyMetricEntry.Notes")
        } header: {
            Text("Optional")
                .font(MarbleTypography.sectionTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
        }
    }

    private var scoringSection: some View {
        Section {
            Picker("Scoring", selection: $dotsUsesFemaleCoefficients) {
                Text("Men").tag(false)
                Text("Women").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("BodyMetricEntry.DotsCoefficients")
        } header: {
            Text("Relative Strength")
                .font(MarbleTypography.sectionTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
        } footer: {
            Text("DOTS scores a lift against bodyweight using sex-specific coefficients. This only affects the relative-strength line in Trends.")
                .font(MarbleTypography.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Load + save

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        guard let entry else {
            unit = preferredWeightUnit
            return
        }
        unit = preferredWeightUnit
        weight = entry.displayWeight(in: unit)
        bodyFatPercent = entry.bodyFatPercent
        measuredAt = entry.measuredAt
        notes = entry.notes ?? ""
    }

    private func save() {
        guard let kilograms = canonicalKilograms else { return }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedNotes = trimmedNotes.isEmpty ? nil : trimmedNotes
        // Body fat is percentage points; anything outside 0…100 is a typo, not
        // a measurement.
        let resolvedBodyFat = bodyFatPercent.flatMap { (0...100).contains($0) ? $0 : nil }

        if let entry {
            entry.weightKilograms = kilograms
            entry.bodyFatPercent = resolvedBodyFat
            entry.measuredAt = measuredAt
            entry.notes = resolvedNotes
            entry.updatedAt = AppEnvironment.now
            // A hand-edited Health sample is now the lifter's own number, but
            // the HealthKit UUID stays so a re-import doesn't duplicate it.
            entry.source = .manual
        } else {
            modelContext.insert(BodyMetricEntry(
                measuredAt: measuredAt,
                weightKilograms: kilograms,
                bodyFatPercent: resolvedBodyFat,
                source: .manual,
                notes: resolvedNotes
            ))
        }

        if modelContext.saveOrRollback() {
            MarbleHaptics.lightImpact()
        }
        dismiss()
    }
}
