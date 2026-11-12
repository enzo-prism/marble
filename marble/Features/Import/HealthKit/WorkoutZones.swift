import Foundation
import HealthKit
import SwiftUI

nonisolated struct WorkoutZoneRow: Identifiable, Sendable, Equatable {
    let id: Int
    let lowerBeatsPerMinute: Int?
    let upperBeatsPerMinute: Int?
    let seconds: Double
    let source: String
    var rangeText: String {
        switch (lowerBeatsPerMinute, upperBeatsPerMinute) {
        case let (lower?, upper?): "\(lower)–\(upper) bpm"
        case let (lower?, nil): "\(lower)+ bpm"
        case let (nil, upper?): "Below \(upper) bpm"
        default: "Heart rate"
        }
    }
}

@available(iOS 27.0, *)
@MainActor
enum WorkoutZones {
    static func load(workoutID: UUID) async -> [WorkoutZoneRow] {
        let store = HKHealthStore()
        let workout: HKWorkout? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: HKQuery.predicateForObject(with: workoutID), limit: 1, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: samples?.first as? HKWorkout)
            }
            store.execute(query)
        }
        guard let group = workout?.zoneGroup(for: HKQuantityType(.heartRate)) else { return [] }
        let source: String
        switch group.configuration.source {
        case .system: source = "Health system zones"
        case .user: source = "Your Health zones"
        case .app: source = "Recording app's zones"
        @unknown default: source = "Recorded workout zones"
        }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        return group.zoneDurations.enumerated().compactMap { offset, duration in
            guard duration.duration.isFinite, duration.duration >= 0 else { return nil }
            return WorkoutZoneRow(id: offset + 1,
                lowerBeatsPerMinute: duration.zone.minimum.map { Int($0.doubleValue(for: bpm).rounded()) },
                upperBeatsPerMinute: duration.zone.maximum.map { Int($0.doubleValue(for: bpm).rounded()) },
                seconds: duration.duration, source: source)
        }
    }
}

struct WorkoutZonesView: View {
    let rows: [WorkoutZoneRow]
    private var total: Double { rows.reduce(0) { $0 + $1.seconds } }
    var body: some View {
        if !rows.isEmpty, total > 0 {
            VStack(alignment: .leading, spacing: 12) {
                Text("Heart Rate Zones").font(.headline)
                Text(rows[0].source).font(.caption).foregroundStyle(.secondary)
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Zone \(row.id) · \(row.rangeText)")
                            Spacer(minLength: 8)
                            Text(DateHelper.formattedDuration(seconds: Int(row.seconds.rounded())))
                        }
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        ProgressView(value: row.seconds, total: total).tint(.primary)
                            .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Zones use this workout's recorded thresholds. Different zone configurations may not be directly comparable.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
