import Combine
import SwiftUI

struct RestTimerView: View {
    let totalSeconds: Int

    @State private var remainingSeconds: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(totalSeconds: Int) {
        self.totalSeconds = totalSeconds
        _remainingSeconds = State(initialValue: totalSeconds)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Rest")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

            Text(DateHelper.formattedDuration(seconds: remainingSeconds))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .tint(Theme.primaryTextColor(for: colorScheme))
            .accessibilityIdentifier("RestTimer.Done")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundColor(for: colorScheme))
        .onReceive(timer) { _ in
            guard remainingSeconds > 0 else { return }
            remainingSeconds -= 1
        }
    }
}
