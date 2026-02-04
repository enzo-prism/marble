import Foundation

enum SupplementTrendDisplayMode: Equatable {
    case count(reason: SupplementCountReason)
    case dose(unit: SupplementUnit)
}

enum SupplementCountReason: Equatable {
    case allSupplements
    case noDoseData
    case mixedUnits
}

struct SupplementDailySummary: Identifiable {
    let date: Date
    let entries: [SupplementEntry]
    let mode: SupplementTrendDisplayMode

    var id: Date { date }
    var count: Int { entries.count }
    var uniqueTypeCount: Int { Set(entries.map { $0.type.id }).count }
    var totalDose: Double { entries.compactMap { $0.dose }.reduce(0, +) }
    var missingDoseCount: Int { entries.filter { $0.dose == nil }.count }

    var chartValue: Double {
        switch mode {
        case .dose:
            return totalDose
        case .count:
            return Double(count)
        }
    }

    var valueText: String {
        switch mode {
        case .dose(let unit):
            let formatted = Formatters.dose.string(from: NSNumber(value: totalDose)) ?? "\(totalDose)"
            return "\(formatted) \(unit.displayName)"
        case .count:
            return logLabel(count)
        }
    }

    var summaryText: String? {
        switch mode {
        case .dose:
            var parts = [logLabel(count)]
            if missingDoseCount > 0 {
                parts.append(missingDoseLabel(missingDoseCount))
            }
            return parts.joined(separator: " · ")
        case .count(let reason):
            switch reason {
            case .allSupplements:
                return uniqueTypeCount > 0 ? typeLabel(uniqueTypeCount) : nil
            case .noDoseData:
                return "Dose not logged"
            case .mixedUnits:
                return "Mixed units"
            }
        }
    }

    private func logLabel(_ count: Int) -> String {
        count == 1 ? "1 log" : "\(count) logs"
    }

    private func missingDoseLabel(_ count: Int) -> String {
        count == 1 ? "1 missing dose" : "\(count) missing doses"
    }

    private func typeLabel(_ count: Int) -> String {
        count == 1 ? "1 type" : "\(count) types"
    }
}
