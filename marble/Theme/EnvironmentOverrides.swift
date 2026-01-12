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
