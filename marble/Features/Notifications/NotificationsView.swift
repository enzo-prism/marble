import SwiftData
import SwiftUI
import UIKit

struct NotificationsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @Query(sort: \CustomNotification.createdAt)
    private var notifications: [CustomNotification]

    @State private var authorizationStatus: CustomNotificationAuthorizationStatus = .notDetermined
    @State private var showingNewNotification = false
    @State private var editingNotification: CustomNotification?

    private let scheduler: CustomNotificationScheduler

    init(scheduler: CustomNotificationScheduler) {
        self.scheduler = scheduler
    }

    var body: some View {
        List {
            permissionSection

            Section {
                if orderedNotifications.isEmpty {
                    emptyState
                        .listRowSeparator(.hidden)
                        .listRowBackground(Theme.backgroundColor(for: colorScheme))
                } else {
                    ForEach(orderedNotifications) { notification in
                        NotificationRowView(
                            notification: notification,
                            timeText: timeText(for: notification),
                            daysText: daysText(for: notification),
                            isOn: enabledBinding(for: notification),
                            onEdit: { editingNotification = notification }
                        )
                        .marbleRowInsets()
                    }
                    .onDelete(perform: deleteNotifications)
                }
            } header: {
                SectionHeaderView(title: "Custom")
            } footer: {
                if notifications.count >= CustomNotification.maximumCount {
                    Text("10 notification limit reached.")
                        .font(MarbleTypography.caption)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .accessibilityIdentifier("Notifications.MaxLimit")
                }
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Theme.subtleDividerColor(for: colorScheme))
        .scrollContentBackground(.hidden)
        .contentMargins(.top, MarbleSpacing.xs, for: .scrollContent)
        .background(Theme.backgroundColor(for: colorScheme))
        .accessibilityIdentifier("Notifications.List")
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarGlassBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewNotification = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(notifications.count >= CustomNotification.maximumCount)
                .accessibilityLabel("Add Notification")
                .accessibilityIdentifier("Notifications.Add")
            }
        }
        .sheet(isPresented: $showingNewNotification) {
            NavigationStack {
                NotificationEditorView(notification: nil, scheduler: scheduler)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .sheetGlassBackground()
        }
        .sheet(item: $editingNotification) { notification in
            NavigationStack {
                NotificationEditorView(notification: notification, scheduler: scheduler)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .sheetGlassBackground()
        }
        .task {
            authorizationStatus = await scheduler.authorizationStatus()
        }
    }

    private var permissionSection: some View {
        Section {
            HStack(alignment: .center, spacing: MarbleSpacing.s) {
                Image(systemName: permissionIconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .frame(width: MarbleLayout.rowIconSize, height: MarbleLayout.rowIconSize)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: MarbleLayout.rowInnerSpacing) {
                    Text(permissionTitle)
                        .font(MarbleTypography.rowTitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        .accessibilityIdentifier("Notifications.Permission.Title")
                    Text(permissionMessage)
                        .font(MarbleTypography.rowSubtitle)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("Notifications.Permission.Message")
                }

                Spacer(minLength: MarbleSpacing.s)

                if authorizationStatus == .notDetermined {
                    Button("Enable") {
                        requestPermission()
                    }
                    .buttonStyle(MarbleActionButtonStyle())
                    .accessibilityIdentifier("Notifications.Permission.Enable")
                } else if authorizationStatus == .denied {
                    Button("Settings") {
                        openSettings()
                    }
                    .buttonStyle(MarbleActionButtonStyle())
                    .accessibilityIdentifier("Notifications.Permission.Settings")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: MarbleSpacing.m) {
            EmptyStateView(
                title: "No notifications",
                message: "Add a custom reminder.",
                systemImage: "bell"
            )

            Button("Add Notification") {
                showingNewNotification = true
            }
            .buttonStyle(MarbleActionButtonStyle(prominence: .primary))
            .accessibilityIdentifier("Notifications.Empty.Add")
        }
    }

    private var orderedNotifications: [CustomNotification] {
        notifications.sorted {
            if $0.hour != $1.hour {
                return $0.hour < $1.hour
            }
            if $0.minute != $1.minute {
                return $0.minute < $1.minute
            }
            return $0.createdAt < $1.createdAt
        }
    }

    private var permissionIconName: String {
        switch authorizationStatus {
        case .authorized:
            return "bell.badge"
        case .notDetermined:
            return "bell"
        case .denied:
            return "bell.slash"
        }
    }

    private var permissionTitle: String {
        switch authorizationStatus {
        case .authorized:
            return "Notifications On"
        case .notDetermined:
            return "Permission Needed"
        case .denied:
            return "Notifications Off"
        }
    }

    private var permissionMessage: String {
        switch authorizationStatus {
        case .authorized:
            return "Marble can send reminders."
        case .notDetermined:
            return "Enable reminders when you save."
        case .denied:
            return "Turn on notifications in Settings."
        }
    }

    private func enabledBinding(for notification: CustomNotification) -> Binding<Bool> {
        Binding(
            get: { notification.isEnabled },
            set: { isEnabled in
                notification.isEnabled = isEnabled
                notification.updatedAt = AppEnvironment.now
                try? modelContext.save()
                Task {
                    _ = await scheduler.sync(notification)
                    authorizationStatus = await scheduler.authorizationStatus()
                }
            }
        )
    }

    private func deleteNotifications(at offsets: IndexSet) {
        for offset in offsets {
            let notification = orderedNotifications[offset]
            scheduler.remove(notification)
            modelContext.delete(notification)
        }
        try? modelContext.save()
    }

    private func requestPermission() {
        Task {
            authorizationStatus = await scheduler.requestAuthorization()
            if authorizationStatus == .authorized {
                for notification in notifications where notification.isEnabled {
                    _ = await scheduler.sync(notification)
                }
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func timeText(for notification: CustomNotification) -> String {
        Formatters.time.string(from: notification.timeDate())
    }

    private func daysText(for notification: CustomNotification) -> String {
        let weekdays = notification.selectedWeekdays
        let selected = Set(weekdays)
        if selected.count == Weekday.allCases.count {
            return "Every day"
        }
        if selected == Set([.monday, .tuesday, .wednesday, .thursday, .friday]) {
            return "Weekdays"
        }
        if selected == Set([.saturday, .sunday]) {
            return "Weekends"
        }
        return weekdays.map(\.shortName).joined(separator: ", ")
    }
}

private struct NotificationRowView: View {
    let notification: CustomNotification
    let timeText: String
    let daysText: String
    let isOn: Binding<Bool>
    let onEdit: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: MarbleSpacing.s) {
            Button {
                onEdit()
            } label: {
                VStack(alignment: .leading, spacing: MarbleLayout.rowInnerSpacing) {
                    Text(notification.trimmedMessage)
                        .font(MarbleTypography.rowTitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(timeText) - \(daysText)")
                        .font(MarbleTypography.rowSubtitle)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("Notifications.Row.\(notification.id.uuidString)")

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Theme.toggleOnColor)
                .accessibilityLabel(notification.isEnabled ? "Disable notification" : "Enable notification")
                .accessibilityIdentifier("Notifications.Toggle.\(notification.id.uuidString)")
        }
        .accessibilityElement(children: .contain)
    }
}
