import SwiftUI

struct OptionalNumberField: View {
    let title: String
    let formatter: NumberFormatter
    @Binding var value: Double?
    var accessibilityIdentifier: String?

    var body: some View {
        let field = TextField(title, text: Binding(
            get: {
                guard let value else { return "" }
                return formatter.string(from: NSNumber(value: value)) ?? ""
            },
            set: { newValue in
                let normalized = newValue.replacingOccurrences(of: ",", with: ".")
                if let number = Double(normalized) {
                    value = number
                } else if newValue.isEmpty {
                    value = nil
                }
            }
        ))
        .keyboardType(.decimalPad)
        .monospacedDigit()
        .marbleFieldStyle()

        if let accessibilityIdentifier {
            field.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            field
        }
    }
}

struct OptionalIntegerField: View {
    let title: String
    @Binding var value: Int?
    var accessibilityIdentifier: String?

    var body: some View {
        let field = TextField(title, text: Binding(
            get: {
                guard let value else { return "" }
                return String(value)
            },
            set: { newValue in
                if let number = Int(newValue) {
                    value = number
                } else if newValue.isEmpty {
                    value = nil
                }
            }
        ))
        .keyboardType(.numberPad)
        .monospacedDigit()
        .marbleFieldStyle()

        if let accessibilityIdentifier {
            field.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            field
        }
    }
}
