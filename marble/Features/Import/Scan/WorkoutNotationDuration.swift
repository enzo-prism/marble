import Foundation

/// Pure duration decoding shared by workout and rest notation. User-entered
/// numbers must never overflow an integer conversion or clock arithmetic.
nonisolated enum WorkoutNotationDuration {
    static func wholeSeconds(_ value: Double) -> Int? {
        guard value.isFinite, value >= 0, value < Double(Int.max) else { return nil }
        return Int(value)
    }

    static func seconds(_ token: String) -> Int? {
        if token.contains(":") {
            let parts = token.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2 || parts.count == 3 else { return nil }
            var total = 0
            for part in parts {
                guard let value = Int(part), value >= 0 else { return nil }
                let product = total.multipliedReportingOverflow(by: 60)
                guard !product.overflow else { return nil }
                let sum = product.partialValue.addingReportingOverflow(value)
                guard !sum.overflow else { return nil }
                total = sum.partialValue
            }
            return total
        }
        let units: [(String, Int)] = [
            ("hours", 3600), ("hour", 3600), ("hrs", 3600), ("hr", 3600), ("h", 3600),
            ("minutes", 60), ("minute", 60), ("mins", 60), ("min", 60),
            ("seconds", 1), ("second", 1), ("secs", 1), ("sec", 1), ("s", 1)
        ]
        for (suffix, multiplier) in units where token.hasSuffix(suffix) {
            guard let value = Double(token.dropLast(suffix.count)) else { continue }
            return wholeSeconds((value * Double(multiplier)).rounded())
        }
        return nil
    }
}
