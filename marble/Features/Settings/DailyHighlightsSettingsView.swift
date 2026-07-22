import SwiftUI

struct DailyHighlightsSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var isEnabled: Bool
    @State private var startMinute: Int
    @State private var endMinute: Int

    init(defaults: UserDefaults = SharedDefaults.suite) {
        _isEnabled = State(initialValue: defaults.object(forKey: SharedDefaults.Key.dailyHighlightsEnabled) as? Bool ?? true)
        _startMinute = State(initialValue: defaults.object(forKey: SharedDefaults.Key.dailyHighlightsStartMinute) as? Int ?? DailyHighlightWindow.defaultStartMinute)
        _endMinute = State(initialValue: defaults.object(forKey: SharedDefaults.Key.dailyHighlightsEndMinute) as? Int ?? DailyHighlightWindow.defaultEndMinute)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show Daily Highlights", isOn: $isEnabled)
                        .tint(Theme.dividerColor(for: colorScheme))
                        .accessibilityIdentifier("DailyHighlights.Enabled")
                }

                Section("Window") {
                    DatePicker("Starts", selection: timeBinding(for: $startMinute), displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("DailyHighlights.Start")
                    DatePicker("Ends", selection: timeBinding(for: $endMinute), displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("DailyHighlights.End")

                    if isValid {
                        Text(windowExplanation)
                            .font(MarbleTypography.caption)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    } else {
                        Text("Start and end can’t be the same.")
                            .font(MarbleTypography.caption)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                            .accessibilityIdentifier("DailyHighlights.Validation")
                    }
                }

                Section("Sharing") {
                    Text("Shared images include exercise names and workout numbers. Notes, body measurements, locations, and supplement details are never included.")
                        .font(MarbleTypography.caption)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }

                Section {
                    Button("Use 8:00 PM–11:59 PM") {
                        startMinute = DailyHighlightWindow.defaultStartMinute
                        endMinute = DailyHighlightWindow.defaultEndMinute
                        MarbleHaptics.selection()
                    }
                    .accessibilityIdentifier("DailyHighlights.Reset")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundColor(for: colorScheme))
            .navigationTitle("Daily Highlights")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                        .accessibilityIdentifier("DailyHighlights.Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save)
                        .disabled(!isValid)
                        .accessibilityIdentifier("DailyHighlights.Done")
                }
            }
        }
    }

    private var isValid: Bool {
        DailyHighlightWindow(startMinute: startMinute, endMinute: endMinute).isValid
    }

    private var windowExplanation: String {
        let start = formattedTime(startMinute)
        let end = formattedTime(endMinute)
        let overnight = endMinute < startMinute ? " Ends the next day." : ""
        return "Your highlights appear in Trends from \(start) through \(end) and refresh with anything you log for that day.\(overnight)"
    }

    private func timeBinding(for minute: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { date(for: minute.wrappedValue) },
            set: { newValue in
                let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: newValue)
                minute.wrappedValue = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }

    private func date(for minute: Int) -> Date {
        let calendar = Calendar.autoupdatingCurrent
        let day = calendar.startOfDay(for: AppEnvironment.now)
        return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day) ?? day
    }

    private func formattedTime(_ minute: Int) -> String {
        date(for: minute).formatted(date: .omitted, time: .shortened)
    }

    private func save() {
        guard isValid else { return }
        let defaults = SharedDefaults.suite
        defaults.set(isEnabled, forKey: SharedDefaults.Key.dailyHighlightsEnabled)
        defaults.set(startMinute, forKey: SharedDefaults.Key.dailyHighlightsStartMinute)
        defaults.set(endMinute, forKey: SharedDefaults.Key.dailyHighlightsEndMinute)
        MarbleHaptics.success()
        dismiss()
    }
}
