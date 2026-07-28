import SwiftUI

struct OptionalNumberField: View {
    let title: String
    let formatter: NumberFormatter
    @Binding var value: Double?
    var accessibilityIdentifier: String?

    var body: some View {
        // Grouping separators must never reach an editable field: the setter
        // treats every "," as a decimal point (that's how comma-decimal
        // locales type fractions on the decimal pad), so a displayed "1,500"
        // edited in place would silently collapse to 1.5.
        let editingFormatter: NumberFormatter = {
            guard formatter.usesGroupingSeparator,
                  let copy = formatter.copy() as? NumberFormatter else { return formatter }
            copy.usesGroupingSeparator = false
            return copy
        }()
        let field = TextField(title, text: Binding(
            get: {
                guard let value else { return "" }
                return editingFormatter.string(from: NSNumber(value: value)) ?? ""
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
