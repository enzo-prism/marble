import Foundation

enum SnapshotRecording {
    private static let markerPath: String = {
        let temp = NSTemporaryDirectory()
        return (temp as NSString).appendingPathComponent("marble_snapshot_recording")
    }()

    static var isEnabled: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["RECORD_SNAPSHOTS"] == "1" {
            return true
        }
        if env["SNAPSHOT_TESTING_RECORD"]?.lowercased() == "all" {
            return true
        }
        if FileManager.default.fileExists(atPath: markerPath) {
            return true
        }
        if CommandLine.arguments.contains("RECORD_SNAPSHOTS=1") {
            return true
        }
        if CommandLine.arguments.contains("SNAPSHOT_TESTING_RECORD=all") {
            return true
        }
        return false
    }
}
