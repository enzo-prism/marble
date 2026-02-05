import SnapshotTesting
import SwiftUI
import XCTest
@testable import marble

struct SnapshotDevice {
    let name: String
    let size: CGSize
    let safeArea: UIEdgeInsets
}

struct SnapshotVariant {
    let colorScheme: ColorScheme
    let sizeCategory: ContentSizeCategory
    let device: SnapshotDevice

    var suffix: String {
        let scheme = colorScheme == .dark ? "dark" : "light"
        let size = sizeCategory.isAccessibilityCategory ? "a11y" : "default"
        return "\(device.name)_\(scheme)_\(size)"
    }
}

enum SnapshotMatrix {
    static let devices: [SnapshotDevice] = [
        SnapshotDevice(name: "iPhoneSE", size: CGSize(width: 375, height: 667), safeArea: UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)),
        SnapshotDevice(name: "iPhone15Pro", size: CGSize(width: 393, height: 852), safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0))
    ]

    static let variants: [SnapshotVariant] = {
        let schemes: [ColorScheme] = [.light, .dark]
        let sizes: [ContentSizeCategory] = [.large, .accessibilityExtraExtraExtraLarge]
        var all: [SnapshotVariant] = []
        for device in devices {
            for scheme in schemes {
                for size in sizes {
                    all.append(SnapshotVariant(colorScheme: scheme, sizeCategory: size, device: device))
                }
            }
        }
        return all
    }()
}

func assertSnapshot<V: View>(
    _ view: V,
    named name: String,
    file: StaticString = #file,
    testName: String = #function,
    line: UInt = #line
) {
    for variant in SnapshotMatrix.variants {
        let activityName = "\(name)_\(variant.suffix)"
        XCTContext.runActivity(named: activityName) { _ in
            let configured = view
                .environment(\.colorScheme, variant.colorScheme)
                .environment(\.sizeCategory, variant.sizeCategory)
                .transaction { $0.disablesAnimations = true }
                .frame(width: variant.device.size.width, height: variant.device.size.height)
                .background(Theme.backgroundColor(for: variant.colorScheme))

            let controller = UIHostingController(rootView: configured)
            controller.view.backgroundColor = UIColor(Theme.backgroundColor(for: variant.colorScheme))

            let traits = UITraitCollection(traitsFrom: [
                UITraitCollection(userInterfaceIdiom: .phone),
                UITraitCollection(userInterfaceStyle: variant.colorScheme == .dark ? .dark : .light),
                UITraitCollection(preferredContentSizeCategory: uiContentSizeCategory(from: variant.sizeCategory))
            ])

            let config = ViewImageConfig(
                safeArea: variant.device.safeArea,
                size: variant.device.size,
                traits: traits
            )

            RunLoop.main.run(until: Date().addingTimeInterval(0.05))

            let failure = verifySnapshot(
                of: controller,
                as: .image(on: config, precision: 0.98),
                named: activityName,
                file: file,
                testName: testName,
                line: line
            )

            if let failure, !shouldIgnoreSnapshotFailure() {
                XCTFail(failure, file: file, line: line)
            }
        }
    }
}

private func shouldIgnoreSnapshotFailure() -> Bool {
    SnapshotRecording.isEnabled
}

private func uiContentSizeCategory(from sizeCategory: ContentSizeCategory) -> UIContentSizeCategory {
    switch sizeCategory {
    case .extraSmall:
        return .extraSmall
    case .small:
        return .small
    case .medium:
        return .medium
    case .large:
        return .large
    case .extraLarge:
        return .extraLarge
    case .extraExtraLarge:
        return .extraExtraLarge
    case .extraExtraExtraLarge:
        return .extraExtraExtraLarge
    case .accessibilityMedium:
        return .accessibilityMedium
    case .accessibilityLarge:
        return .accessibilityLarge
    case .accessibilityExtraLarge:
        return .accessibilityExtraLarge
    case .accessibilityExtraExtraLarge:
        return .accessibilityExtraExtraLarge
    case .accessibilityExtraExtraExtraLarge:
        return .accessibilityExtraExtraExtraLarge
    default:
        return .large
    }
}
