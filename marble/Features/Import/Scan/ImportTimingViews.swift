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

    /// Off by default: most notes carry a day, not a clock time. Turning it off
    /// keeps whatever time the date already holds — zeroing it would silently
    /// move already-adjusted sets to midnight.
    @State private var includeTime = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Section {
            HStack {
                Text("Date")
                Spacer()
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

            Toggle("Include Time", isOn: $includeTime.animation())
                .tint(Theme.dividerColor(for: colorScheme))
                .accessibilityIdentifier("\(idPrefix).IncludeTime")

            if includeTime {
                HStack {
                    Text("Time")
                    Spacer()
                    DatePicker(
                        "Time",
                        selection: dateBinding,
                        displayedComponents: [.hourAndMinute]
                    )
                    .labelsHidden()
                    .accessibilityIdentifier("\(idPrefix).Time")
                }
            }
        } footer: {
            Text("Applied to every set unless a set has its own date & time.")
                .font(MarbleTypography.caption)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        }
    }

    /// nil → "now" adapter. A compact picker only mutates its displayed
    /// components, so the date and time pickers can safely share this binding.
    private var dateBinding: Binding<Date> {
        Binding(
            get: { performedAt ?? AppEnvironment.now },
            set: { performedAt = $0 }
        )
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
            .accessibilityIdentifier("\(idPrefix).Set.OverrideDate")

            DatePicker(
                "Set time",
                selection: overrideBinding,
                displayedComponents: [.hourAndMinute]
            )
            .labelsHidden()
            .accessibilityIdentifier("\(idPrefix).Set.OverrideTime")

            Spacer()

            Button(action: removeOverride) {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove date & time override")
            .accessibilityIdentifier("\(idPrefix).Set.RemoveOverride")
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
        withAnimation { set.performedAt = workoutDate ?? AppEnvironment.now }
    }

    private func removeOverride() {
        withAnimation { set.performedAt = nil }
    }
}
