import SwiftUI

struct DurationPicker: View {
    @Binding var durationSeconds: Int?

    private let minuteRange = Array(0...30)
    private let secondRange = stride(from: 0, through: 55, by: 5).map { $0 }

    var body: some View {
        HStack(spacing: MarbleSpacing.s) {
            Picker("Minutes", selection: minutesBinding) {
                ForEach(minuteRange, id: \.self) { minute in
                    Text("\(minute)m").tag(minute)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("DurationPicker.Minutes")

            Picker("Seconds", selection: secondsBinding) {
                ForEach(secondRange, id: \.self) { second in
                    Text("\(second)s").tag(second)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("DurationPicker.Seconds")
        }
        .accessibilityElement(children: .combine)
    }

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { (durationSeconds ?? 0) / 60 },
            set: { newValue in
                let seconds = (durationSeconds ?? 0) % 60
                durationSeconds = (newValue * 60) + seconds
            }
        )
    }

    private var secondsBinding: Binding<Int> {
        Binding(
            get: { (durationSeconds ?? 0) % 60 },
            set: { newValue in
                let minutes = (durationSeconds ?? 0) / 60
                durationSeconds = (minutes * 60) + newValue
            }
        )
    }
}
