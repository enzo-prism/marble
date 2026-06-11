import SwiftUI

struct DurationPicker: View {
    @Binding var durationSeconds: Int?

    @Environment(\.colorScheme) private var colorScheme

    private let hourRange = Array(0...12)
    private let minuteRange = Array(0...59)
    private let secondRange = Array(0...59)

    var body: some View {
        HStack(spacing: MarbleSpacing.s) {
            Picker("Hours", selection: hoursBinding) {
                ForEach(hourRange, id: \.self) { hour in
                    Text("\(hour)h").tag(hour)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(Theme.primaryTextColor(for: colorScheme))
            .accessibilityLabel("Hours")
            .accessibilityIdentifier("DurationPicker.Hours")

            Picker("Minutes", selection: minutesBinding) {
                ForEach(minuteRange, id: \.self) { minute in
                    Text("\(minute)m").tag(minute)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(Theme.primaryTextColor(for: colorScheme))
            .accessibilityLabel("Minutes")
            .accessibilityIdentifier("DurationPicker.Minutes")

            Picker("Seconds", selection: secondsBinding) {
                ForEach(secondRange, id: \.self) { second in
                    Text("\(second)s").tag(second)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(Theme.primaryTextColor(for: colorScheme))
            .accessibilityLabel("Seconds")
            .accessibilityIdentifier("DurationPicker.Seconds")
        }
    }

    private var hoursBinding: Binding<Int> {
        Binding(
            get: { (durationSeconds ?? 0) / 3600 },
            set: { newValue in
                let belowHours = (durationSeconds ?? 0) % 3600
                durationSeconds = (newValue * 3600) + belowHours
            }
        )
    }

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { ((durationSeconds ?? 0) % 3600) / 60 },
            set: { newValue in
                let hours = (durationSeconds ?? 0) / 3600
                let seconds = (durationSeconds ?? 0) % 60
                durationSeconds = (hours * 3600) + (newValue * 60) + seconds
            }
        )
    }

    private var secondsBinding: Binding<Int> {
        Binding(
            get: { (durationSeconds ?? 0) % 60 },
            set: { newValue in
                let wholeMinutes = (durationSeconds ?? 0) / 60
                durationSeconds = (wholeMinutes * 60) + newValue
            }
        )
    }
}
