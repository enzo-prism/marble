import Foundation
import UIKit

/// The eras your marble civilization advances through. Each age stays fully
/// monochrome — progress reads as more intricate stonework, not more colour.
enum EmpireAge: Int, CaseIterable, Identifiable, Comparable {
    case foundations
    case golden
    case empire
    case industrial
    case future

    var id: Int { rawValue }

    static func < (lhs: EmpireAge, rhs: EmpireAge) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .foundations:
            return "Foundations"
        case .golden:
            return "Golden Age"
        case .empire:
            return "Age of Empire"
        case .industrial:
            return "Industrial Age"
        case .future:
            return "The Future"
        }
    }

    var tagline: String {
        switch self {
        case .foundations:
            return "Quarry the first stones of your city."
        case .golden:
            return "Raise temples worthy of the gods."
        case .empire:
            return "Span the known world in marble."
        case .industrial:
            return "Forge the engines of a new age."
        case .future:
            return "Carve a monument that outlasts time."
        }
    }
}

/// A single buildable monument. The catalog is static data (like `SeedData`'s
/// exercise rows); `EmpireState` only records which `id`s have been built.
struct EmpireStructure: Identifiable, Hashable {
    let id: String
    let name: String
    let flavor: String
    let symbolName: String
    /// Relative height in the skyline, 0...1.
    let scale: CGFloat
    let cost: Double
    let age: EmpireAge

    /// Falls back to a safe glyph if the preferred SF Symbol is unavailable on the
    /// running OS, mirroring `ExerciseCategory`'s symbol resolution.
    var resolvedSymbolName: String {
        UIImage(systemName: symbolName) != nil ? symbolName : "building.columns"
    }
}

enum EmpireEconomy {
    /// Talents are earned 1:1 with the app's existing composite effort score, so the
    /// currency always matches what Trends already shows: weight×reps for loaded sets,
    /// reps for bodyweight work, and a minute of duration for timed work.
    /// (A 10 lb vest × 10 squats banks 100 Talents — the user's "$1 per pound" model.)
    static func lifetimeTalents(from entries: [SetEntry]) -> Double {
        volumeScore(of: entries)
    }

    static func talentsEarned(on day: Date, from entries: [SetEntry], calendar: Calendar = .current) -> Double {
        let dayEntries = entries.filter { calendar.isDate($0.performedAt, inSameDayAs: day) }
        return volumeScore(of: dayEntries)
    }

    /// Composite effort score: weight×reps for loaded sets, reps for bodyweight work, and
    /// one Talent per minute of duration. Mirrors the volume math Trends displays, but kept
    /// self-contained so the Empire economy doesn't depend on Trends internals.
    private static func volumeScore(of entries: [SetEntry]) -> Double {
        var weighted = 0.0
        var reps = 0
        var durationSeconds = 0
        for entry in entries {
            if let weight = entry.weight, let entryReps = entry.reps {
                weighted += weight * Double(entryReps)
            } else if let entryReps = entry.reps {
                reps += entryReps
            }
            if let duration = entry.durationSeconds {
                durationSeconds += duration
            }
        }
        return weighted + Double(reps) + Double(durationSeconds) / 60.0
    }

    static let catalog: [EmpireStructure] = [
        // MARK: Foundations — the first Greek settlement
        EmpireStructure(id: "quarry", name: "The Quarry", flavor: "Where every great city begins.", symbolName: "mountain.2.fill", scale: 0.55, cost: 250, age: .foundations),
        EmpireStructure(id: "altar", name: "Stone Altar", flavor: "An offering for strength.", symbolName: "flame.fill", scale: 0.45, cost: 600, age: .foundations),
        EmpireStructure(id: "column", name: "First Column", flavor: "Doric, unadorned, enduring.", symbolName: "building.columns", scale: 0.7, cost: 1_200, age: .foundations),
        EmpireStructure(id: "agora", name: "The Agora", flavor: "A gathering place takes shape.", symbolName: "building.columns.fill", scale: 0.65, cost: 2_500, age: .foundations),

        // MARK: Golden Age — classical Greece
        EmpireStructure(id: "temple", name: "Marble Temple", flavor: "Fluted columns catch the light.", symbolName: "building.columns.fill", scale: 0.85, cost: 5_000, age: .golden),
        EmpireStructure(id: "theatre", name: "Amphitheatre", flavor: "Ten thousand voices, one stage.", symbolName: "theatermasks.fill", scale: 0.6, cost: 10_000, age: .golden),
        EmpireStructure(id: "statue", name: "Hero's Statue", flavor: "Carved in your own likeness.", symbolName: "figure.stand", scale: 0.75, cost: 18_000, age: .golden),
        EmpireStructure(id: "acropolis", name: "The Acropolis", flavor: "Your city crowns its highest hill.", symbolName: "building.columns.fill", scale: 1.0, cost: 32_000, age: .golden),

        // MARK: Age of Empire — Roman ambition
        EmpireStructure(id: "aqueduct", name: "Aqueduct", flavor: "Water flows where stone leads.", symbolName: "water.waves", scale: 0.5, cost: 55_000, age: .empire),
        EmpireStructure(id: "forum", name: "Grand Forum", flavor: "The heart of a republic.", symbolName: "building.columns", scale: 0.75, cost: 95_000, age: .empire),
        EmpireStructure(id: "arena", name: "The Arena", flavor: "Glory is won in the sand.", symbolName: "sportscourt.fill", scale: 0.7, cost: 160_000, age: .empire),
        EmpireStructure(id: "arch", name: "Triumphal Arch", flavor: "Built for those who endure.", symbolName: "crown.fill", scale: 0.6, cost: 280_000, age: .empire),

        // MARK: Industrial Age
        EmpireStructure(id: "foundry", name: "Iron Foundry", flavor: "Marble meets molten iron.", symbolName: "hammer.fill", scale: 0.55, cost: 500_000, age: .industrial),
        EmpireStructure(id: "clocktower", name: "Clock Tower", flavor: "Time itself keeps your pace.", symbolName: "clock.fill", scale: 0.9, cost: 850_000, age: .industrial),
        EmpireStructure(id: "bridge", name: "Great Bridge", flavor: "Two eras, joined.", symbolName: "road.lanes", scale: 0.4, cost: 1_400_000, age: .industrial),
        EmpireStructure(id: "manufactory", name: "The Manufactory", flavor: "Progress, by the ton.", symbolName: "building.2.fill", scale: 0.85, cost: 2_200_000, age: .industrial),

        // MARK: The Future
        EmpireStructure(id: "observatory", name: "Observatory", flavor: "You set your sights higher.", symbolName: "binoculars.fill", scale: 0.7, cost: 3_500_000, age: .future),
        EmpireStructure(id: "spire", name: "Crystal Spire", flavor: "White stone, reaching skyward.", symbolName: "building", scale: 1.0, cost: 6_000_000, age: .future),
        EmpireStructure(id: "skybridge", name: "Sky Bridge", flavor: "A city among the clouds.", symbolName: "point.3.filled.connected.trianglepath.dotted", scale: 0.5, cost: 11_000_000, age: .future),
        EmpireStructure(id: "monument", name: "Monument to the Athlete", flavor: "The summit of your effort, immortalised.", symbolName: "trophy.fill", scale: 1.0, cost: 22_000_000, age: .future)
    ]

    static func structure(id: String) -> EmpireStructure? {
        catalog.first { $0.id == id }
    }

    static func structures(in age: EmpireAge) -> [EmpireStructure] {
        catalog.filter { $0.age == age }.sorted { $0.cost < $1.cost }
    }

    /// Structures the user has built, ordered for display in the skyline.
    static func builtStructures(ids builtIDs: Set<String>) -> [EmpireStructure] {
        catalog
            .filter { builtIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.age != rhs.age { return lhs.age < rhs.age }
                return lhs.cost < rhs.cost
            }
    }

    static func isAgeComplete(_ age: EmpireAge, builtIDs: Set<String>) -> Bool {
        structures(in: age).allSatisfy { builtIDs.contains($0.id) }
    }

    /// An age unlocks once the previous age is fully built. Foundations is always open.
    static func isAgeUnlocked(_ age: EmpireAge, builtIDs: Set<String>) -> Bool {
        guard age != .foundations else { return true }
        guard let previous = EmpireAge(rawValue: age.rawValue - 1) else { return true }
        return isAgeComplete(previous, builtIDs: builtIDs)
    }

    /// The highest age the user has access to — the era they are currently shaping.
    static func currentAge(builtIDs: Set<String>) -> EmpireAge {
        EmpireAge.allCases.last { isAgeUnlocked($0, builtIDs: builtIDs) } ?? .foundations
    }

    /// The cheapest unbuilt structure in an unlocked age — the user's next concrete goal.
    static func nextGoal(builtIDs: Set<String>) -> EmpireStructure? {
        catalog
            .filter { !builtIDs.contains($0.id) && isAgeUnlocked($0.age, builtIDs: builtIDs) }
            .min { $0.cost < $1.cost }
    }

    static var totalStructureCount: Int { catalog.count }

    static func builtCount(in builtIDs: Set<String>) -> Int {
        catalog.reduce(0) { $0 + (builtIDs.contains($1.id) ? 1 : 0) }
    }
}
