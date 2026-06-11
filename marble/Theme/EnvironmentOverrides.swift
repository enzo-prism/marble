import SwiftUI

private struct MarbleReduceTransparencyOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    var marbleReduceTransparencyOverride: Bool? {
        get { self[MarbleReduceTransparencyOverrideKey.self] }
        set { self[MarbleReduceTransparencyOverrideKey.self] = newValue }
    }
}

private struct MarbleActiveDayKey: EnvironmentKey {
    static let defaultValue: Date = DateHelper.startOfDay(for: AppEnvironment.now)
}

extension EnvironmentValues {
    /// Start of the current day, re-anchored when the scene becomes active or
    /// the system clock crosses a significant boundary. Views that render
    /// relative date labels ("Today", "Yesterday") read this so they
    /// re-evaluate after the app sits in the background past midnight.
    var marbleActiveDay: Date {
        get { self[MarbleActiveDayKey.self] }
        set { self[MarbleActiveDayKey.self] = newValue }
    }
}
