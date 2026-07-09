import Foundation
import SwiftData

@Model
final class WorkoutSession {
    #Index<WorkoutSession>([\.startedAt], [\.endedAt], [\.updatedAt])

    @Attribute(.unique) var id: UUID
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    /// Sessions own grouping, not the underlying history. Deleting a session
    /// leaves its sets intact so a mistaken delete never erases training data.
    @Relationship(deleteRule: .nullify)
    var entries: [SetEntry]

    init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        entries: [SetEntry] = []
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.entries = entries
    }
}

extension WorkoutSession {
    var isActive: Bool { endedAt == nil }

    var duration: TimeInterval {
        max(0, (endedAt ?? AppEnvironment.now).timeIntervalSince(startedAt))
    }

    var orderedEntries: [SetEntry] {
        entries.sorted { lhs, rhs in
            if lhs.performedAt == rhs.performedAt { return lhs.createdAt < rhs.createdAt }
            return lhs.performedAt < rhs.performedAt
        }
    }

    func append(_ entry: SetEntry, at date: Date = AppEnvironment.now) {
        guard !entries.contains(where: { $0.id == entry.id }) else { return }
        entries.append(entry)
        updatedAt = date
    }

    func finish(at date: Date = AppEnvironment.now) {
        endedAt = max(date, startedAt)
        updatedAt = date
    }
}
