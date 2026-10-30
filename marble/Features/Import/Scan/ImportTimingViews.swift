import SwiftUI

/// Shared date & time editing for the import review screens (scan + text entry),
/// following the Calendar-editor pattern: compact date/time pickers that pop a
/// modal calendar over the list. Compact is the only style that belongs inside a
/// `List` row — graphical/wheel pickers would dominate the row and pushing a
/// separate screen for a date is a HIG anti-pattern.

// MARK: - Workout date & time section

/// The workout-level "Date" section of a review list. Binds to the draft's
/// optional `performedAt` (nil = "now at import time") through a non-optional
/// adapter so the picker always has a value to show.
struct ImportDateSection: View {
    /// Leaf a11y-identifier prefix ("TextEntry" / "Scan"). Identifiers go on the
    /// pickers and toggle only — an id on the section would clobber the children.
    let idPrefix: String
    @Binding var performedAt: Date?
    @Binding var notes: String?
    /// Session length from a structured export; hidden for handwritten drafts.
    var durationSeconds: Int? = nil

    /// Off by default: most notes carry a day, not a clock time. Turning it off
    /// keeps whatever time the date already holds — zeroing it would silently
    /// move already-adjusted sets to midnight.
    @State private var includeTime = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Section {
            dateTimeLayout {
                Text("Date")
                    .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer()
                }
                // Upper bound at "now": workouts are imported, never scheduled.
                DatePicker(
                    "Date",
                    selection: dateBinding,
                    in: ...AppEnvironment.now,
                    displayedComponents: [.date]
                )
                .labelsHidden()
                .accessibilityIdentifier("\(idPrefix).Date")
            }

            Toggle("Include Time", isOn: $includeTime.animation(reduceMotion ? nil : .default))
                .tint(Theme.dividerColor(for: colorScheme))
                .accessibilityIdentifier("\(idPrefix).IncludeTime")

            if includeTime {
                dateTimeLayout {
                    Text("Time")
                        .fixedSize(horizontal: false, vertical: true)
                    if !dynamicTypeSize.isAccessibilitySize {
                        Spacer()
                    }
                    DatePicker(
                        "Time",
                        selection: dateBinding,
                        displayedComponents: [.hourAndMinute]
                    )
                    .labelsHidden()
                    .accessibilityIdentifier("\(idPrefix).Time")
                }
            }

            TextField("Workout notes", text: notesBinding, axis: .vertical)
                .font(MarbleTypography.rowSubtitle)
                .lineLimit(1...3)
                .writingToolsBehavior(.disabled)
                .accessibilityIdentifier("\(idPrefix).Notes")
        } footer: {
            VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                Text("Applied to every set unless a set has its own date & time.")
                if let durationLine {
                    Text(durationLine)
                }
                Text("Blank RPE saves as 8. Blank rest uses the exercise default.")
            }
            .font(MarbleTypography.caption)
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
        }
    }

    // At accessibility sizes the native compact picker needs the row's width.
    // Keeping its label beside it compresses "Date" into clipped single letters.
    private var dateTimeLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: MarbleSpacing.xs))
            : AnyLayout(HStackLayout())
    }

    /// nil → "now" adapter. A compact picker only mutates its displayed
    /// components, so the date and time pickers can safely share this binding.
    private var dateBinding: Binding<Date> {
        Binding(
            get: { performedAt ?? AppEnvironment.now },
            set: { performedAt = $0 }
        )
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { notes ?? "" },
            set: { notes = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        )
    }

    private var durationLine: String? {
        guard let durationSeconds, durationSeconds > 0 else { return nil }
        let minutes = durationSeconds / 60
        if minutes >= 120 {
            let hours = minutes / 60
            let remainder = minutes % 60
            if remainder == 0 { return "Export length \(hours)h." }
            return "Export length \(hours)h \(remainder)m."
        }
        if minutes > 0 { return "Export length \(minutes) min." }
        return "Export length \(durationSeconds)s."
    }
}

// MARK: - Per-set override rows

/// Wraps one editable set row with progressive-disclosure date & time override
/// affordances: no timing UI by default; a context menu (mirrored as a leading
/// swipe action, per HIG) activates an override, which reveals an indented
/// compact date + time sub-row bound to `set.performedAt`.
///
/// Adding `.swipeActions` removes the Delete that `.onDelete` used to
/// synthesize on these rows, so an explicit trailing destructive Delete is
/// re-added here, wired to the caller's removal closure.
struct ImportSetTimingRows<Row: View>: View {
    /// Leaf a11y-identifier prefix ("TextEntry" / "Scan").
    let idPrefix: String
    @Binding var set: ParsedSetDraft
    /// The workout-level date; a fresh override starts from it so the sub-row
    /// opens on the value the set would otherwise inherit.
    let workoutDate: Date?
    let onDelete: () -> Void
    @ViewBuilder var row: () -> Row

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
            row()
            // Overridden sets carry a scannable timestamp line so divergent
            // sets stand out without opening either picker.
            if let performedAt = set.performedAt {
                Text(Formatters.fullDateTime.string(from: performedAt))
                    .font(MarbleTypography.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
        }
        .contextMenu { timingMenu }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            // Mirrors the context menu's timing action (HIG: top menu actions
            // should match the row's swipe actions).
            if set.performedAt == nil {
                Button(action: activateOverride) {
                    Label("Set Date & Time", systemImage: "calendar.badge.clock")
                }
            } else {
                Button(action: removeOverride) {
                    Label("Remove Date & Time", systemImage: "calendar.badge.minus")
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }

        if set.performedAt != nil {
            overrideRow
        }
    }

    @ViewBuilder
    private var timingMenu: some View {
        if set.performedAt == nil {
            Button(action: activateOverride) {
                Label("Set Date & Time…", systemImage: "calendar.badge.clock")
            }
        } else {
            Button(action: removeOverride) {
                Label("Remove Date & Time", systemImage: "calendar.badge.minus")
            }
        }
        Button(role: .destructive, action: onDelete) {
            Label("Delete Set", systemImage: "trash")
        }
    }

    /// The indented sub-row: compact date capsule + time capsule bound to the
    /// override, plus a small control that nils it back to "inherit".
    private var overrideRow: some View {
        HStack(spacing: MarbleSpacing.xs) {
            DatePicker(
                "Set date",
                selection: overrideBinding,
                in: ...AppEnvironment.now,
                displayedComponents: [.date]
            )
            .labelsHidden()
            .accessibilityIdentifier("\(idPrefix).Set.OverrideDate.\(set.id.uuidString)")

            DatePicker(
                "Set time",
                selection: overrideBinding,
                displayedComponents: [.hourAndMinute]
            )
            .labelsHidden()
            .accessibilityIdentifier("\(idPrefix).Set.OverrideTime.\(set.id.uuidString)")

            Spacer()

            Button(action: removeOverride) {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove date & time override")
            .accessibilityIdentifier("\(idPrefix).Set.RemoveOverride.\(set.id.uuidString)")
        }
        // Indent under the parent set row so the sub-row reads as belonging to it.
        .padding(.leading, MarbleSpacing.m)
        .padding(.vertical, MarbleSpacing.xxs)
    }

    private var overrideBinding: Binding<Date> {
        Binding(
            get: { set.performedAt ?? workoutDate ?? AppEnvironment.now },
            set: { set.performedAt = $0 }
        )
    }

    private func activateOverride() {
        if reduceMotion {
            set.performedAt = workoutDate ?? AppEnvironment.now
        } else {
            withAnimation { set.performedAt = workoutDate ?? AppEnvironment.now }
        }
    }

    private func removeOverride() {
        if reduceMotion {
            set.performedAt = nil
        } else {
            withAnimation { set.performedAt = nil }
        }
    }
}

// MARK: - Shared review fields

/// Library match picker used by Scan and Paste or Type. Glass stays off this
/// content row — it's a solid list control, not navigation chrome.
struct ImportExerciseMatchRow: View {
    let exerciseName: String
    let exerciseID: UUID
    let idPrefix: String
    let resolution: WorkoutTextEntryViewModel.Resolution?
    var onChoose: (WorkoutTextEntryViewModel.Resolution.Choice) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let resolution {
            Menu {
                ForEach(resolution.suggestions, id: \.candidate.id) { match in
                    Button {
                        onChoose(.library(id: match.candidate.id, name: match.candidate.name))
                    } label: {
                        if case let .library(id, _) = resolution.choice, id == match.candidate.id {
                            Label(match.candidate.name, systemImage: "checkmark")
                        } else {
                            Text(match.candidate.name)
                        }
                    }
                }
                Button {
                    onChoose(.createNew)
                } label: {
                    if resolution.choice == .createNew {
                        Label(createLabel, systemImage: "checkmark")
                    } else {
                        Text(createLabel)
                    }
                }
            } label: {
                HStack(spacing: MarbleSpacing.xs) {
                    Image(systemName: matchIcon)
                        .font(.system(size: 14, weight: .semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(matchTitle)
                            .font(MarbleTypography.rowMeta)
                        if resolution.autoConfidence == .likely {
                            Text("Close match — double-check")
                                .font(MarbleTypography.caption)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .contentShape(Rectangle())
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("\(idPrefix).Exercise.Match.\(exerciseID.uuidString)")
        }
    }

    private var createLabel: String {
        let name = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Create new exercise" : "Create new \"\(name)\""
    }

    private var matchTitle: String {
        switch resolution?.choice {
        case let .library(_, name):
            return "Logs to \(name)"
        case .createNew, nil:
            return "New exercise in your library"
        }
    }

    private var matchIcon: String {
        switch resolution?.choice {
        case .library:
            return "checkmark.circle"
        case .createNew, nil:
            return "plus.circle"
        }
    }
}

/// Rest, RPE, and notes on an import set row. Solid content fields — no glass.
struct ImportSetAnnotationFields: View {
    let idPrefix: String
    @Binding var set: ParsedSetDraft

    var body: some View {
        OptionalIntegerField(
            title: "Rest (sec)",
            value: $set.restSeconds,
            accessibilityIdentifier: "\(idPrefix).Set.Rest.\(set.id.uuidString)"
        )
        OptionalIntegerField(
            title: "RPE",
            value: Binding(
                get: { set.difficulty },
                set: { newValue in
                    guard let newValue else {
                        set.difficulty = nil
                        return
                    }
                    set.difficulty = min(10, max(1, newValue))
                }
            ),
            accessibilityIdentifier: "\(idPrefix).Set.RPE.\(set.id.uuidString)"
        )
        TextField("Notes", text: Binding(
            get: { set.notes ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                set.notes = trimmed.isEmpty ? nil : newValue
            }
        ), axis: .vertical)
        .font(MarbleTypography.rowSubtitle)
        .lineLimit(1...3)
        .writingToolsBehavior(.disabled)
        .accessibilityIdentifier("\(idPrefix).Set.Notes.\(set.id.uuidString)")
    }
}
