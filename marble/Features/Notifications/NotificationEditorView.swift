import SwiftData
import SwiftUI

struct NotificationEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let notification: CustomNotification?
    let scheduler: CustomNotificationScheduler

    @State private var message: String
    @State private var time: Date
    @State private var selectedWeekdays: Set<Weekday>
    @State private var isEnabled: Bool
    @State private var showDeleteConfirmation = false

    init(notification: CustomNotification?, scheduler: CustomNotificationScheduler) {
        self.notification = notification
        self.scheduler = scheduler
        _message = State(initialValue: notification?.message ?? "")
        _time = State(initialValue: notification?.timeDate() ?? Self.defaultTime())
        _selectedWeekdays = State(initialValue: Set(notification?.selectedWeekdays ?? Weekday.allCases))
        _isEnabled = State(initialValue: notification?.isEnabled ?? true)
    }

    var body: some View {
        List {
            Section {
                TextField("Message", text: $message, axis: .vertical)
                    .lineLimit(1...3)
                    .marbleFieldStyle(messageFieldState)
                    .accessibilityIdentifier("NotificationEditor.Message")

                Toggle("Enabled", isOn: $isEnabled)
                    .tint(Theme.dividerColor(for: colorScheme))
                    .accessibilityIdentifier("NotificationEditor.Enabled")
            }

            Section {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .accessibilityIdentifier("NotificationEditor.Time")
            }

            Section {
                weekdayGrid
            } header: {
                SectionHeaderView(title: "Days")
            } footer: {
                if selectedWeekdays.isEmpty {
                    Text("Select at least one day.")
                        .font(MarbleTypography.caption)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .accessibilityIdentifier("NotificationEditor.DayError")
                }
            }

            if notification != nil {
                Section {
                    Button("Delete Notification", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityIdentifier("NotificationEditor.Delete")
                }
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Theme.subtleDividerColor(for: colorScheme))
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme))
        .navigationTitle(notification == nil ? "New Notification" : "Edit Notification")
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
                Button("Cancel") {
                    dismiss()
                }
                .accessibilityIdentifier("NotificationEditor.Cancel")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    save()
                } label: {
                    Text("Save")
                        .fontWeight(.semibold)
                        .foregroundStyle(saveButtonColor)
                }
                .accessibilityValue(canSave ? "Ready" : "Unavailable")
                .accessibilityIdentifier("NotificationEditor.Save")
            }
        }
        .alert("Delete Notification?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteNotification()
            }
            .accessibilityIdentifier("NotificationEditor.ConfirmDelete")

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This reminder will stop immediately.")
        }
    }

    private var weekdayGrid: some View {
        LazyVGrid(columns: weekdayColumns, spacing: MarbleSpacing.xs) {
            ForEach(Weekday.allCases) { weekday in
                Button {
                    toggle(weekday)
                } label: {
                    MarbleChipLabel(
                        title: weekday.shortName,
                        isSelected: selectedWeekdays.contains(weekday),
                        isDisabled: false,
                        isExpanded: true
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(weekday.displayName)
                .accessibilityValue(selectedWeekdays.contains(weekday) ? "Selected" : "Not selected")
                .accessibilityIdentifier("NotificationEditor.Day.\(weekday.shortName)")
            }
        }
        .padding(.vertical, MarbleSpacing.xxs)
    }

    private var weekdayColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 68), spacing: MarbleSpacing.xs)]
    }

    private var canSave: Bool {
        !trimmedMessage.isEmpty && !selectedWeekdays.isEmpty
    }

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var messageFieldState: MarbleFieldState {
        message.isEmpty || !trimmedMessage.isEmpty ? .normal : .error
    }

    private var saveButtonColor: Color {
        canSave ? Theme.primaryTextColor(for: colorScheme) : Theme.secondaryTextColor(for: colorScheme)
    }

    private func toggle(_ weekday: Weekday) {
        if selectedWeekdays.contains(weekday) {
            selectedWeekdays.remove(weekday)
        } else {
            selectedWeekdays.insert(weekday)
        }
    }

    private func save() {
        guard canSave else { return }
        let now = AppEnvironment.now
        let target = notification ?? CustomNotification(message: trimmedMessage, createdAt: now, updatedAt: now)
        target.message = trimmedMessage
        target.setTime(from: time)
        target.setWeekdays(selectedWeekdays)
        target.isEnabled = isEnabled
        target.updatedAt = now

        if notification == nil {
            modelContext.insert(target)
        }
        modelContext.saveOrRollback()

        Task {
            _ = await scheduler.sync(target)
        }
        dismiss()
    }

    private func deleteNotification() {
        guard let notification else { return }
        scheduler.remove(notification)
        modelContext.delete(notification)
        modelContext.saveOrRollback()
        dismiss()
    }

    private static func defaultTime(calendar: Calendar = .current) -> Date {
        let reference = AppEnvironment.now
        var components = calendar.dateComponents([.year, .month, .day], from: reference)
        components.hour = 9
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? reference
    }
}
