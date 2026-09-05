import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import marble

/// History's lazy List needs an appearance/layout cycle before capture. Keep
/// this mounted strategy scoped here until other suites deliberately migrate.
@MainActor
func assertHistorySnapshot<V: View>(
    named name: String,
    expectedText: [String] = [],
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    @ViewBuilder content: () -> V
) {
    for variant in SnapshotMatrix.variants {
        let activityName = "\(name)_\(variant.suffix)"
        XCTContext.runActivity(named: activityName) { _ in
            autoreleasepool {
                let root = UIViewController()
                let host = UIHostingController(rootView: content()
                    .environment(\.colorScheme, variant.colorScheme)
                    .environment(\.sizeCategory, variant.sizeCategory)
                    .environment(\.marbleActiveDay, DateHelper.startOfDay(for: SnapshotFixtures.now))
                    .transaction { $0.disablesAnimations = true })
                let window = HistorySnapshotWindow(size: variant.device.size, insets: variant.device.safeArea)
                let style: UIUserInterfaceStyle = variant.colorScheme == .dark ? .dark : .light
                window.overrideUserInterfaceStyle = style
                root.addChild(host)
                root.view.addSubview(host.view)
                host.view.frame = CGRect(origin: .zero, size: variant.device.size)
                host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                let traits = UITraitCollection { traits in
                    traits.userInterfaceIdiom = variant.device.idiom
                    traits.userInterfaceStyle = style
                    traits.preferredContentSizeCategory = variant.sizeCategory.isAccessibilityCategory
                        ? .accessibilityExtraExtraExtraLarge : .large
                }
                root.setOverrideTraitCollection(traits, forChild: host)
                host.didMove(toParent: root)
                window.rootViewController = root
                window.isHidden = false
                root.beginAppearanceTransition(true, animated: false)
                root.endAppearanceTransition()
                defer {
                    root.beginAppearanceTransition(false, animated: false)
                    root.endAppearanceTransition()
                    window.isHidden = true
                    window.rootViewController = nil
                }

                // Unlike the shared pre-host delay, these turns happen after
                // List and NavigationStack have joined a visible window.
                let earliestCapture = Date().addingTimeInterval(0.5)
                let deadline = Date().addingTimeInterval(3)
                var labels: String = ""
                repeat {
                    root.view.setNeedsLayout()
                    root.view.layoutIfNeeded()
                    host.view.layoutIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                    labels = historyAccessibilityLabels(in: root.view).joined(separator: "\n")
                } while Date() < deadline && (Date() < earliestCapture || !expectedText.allSatisfy(labels.contains))
                guard expectedText.allSatisfy(labels.contains) else {
                    XCTFail("History snapshot did not render expected content: \(expectedText). Labels: \(labels)", file: file, line: line)
                    return
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                root.view.layoutIfNeeded()
                let format = UIGraphicsImageRendererFormat()
                format.scale = 3
                let renderer = UIGraphicsImageRenderer(size: variant.device.size, format: format)
                var rendered = false
                let image = renderer.image { _ in
                    rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                guard rendered else {
                    XCTFail("History window failed to render", file: file, line: line)
                    return
                }
                let verify = {
                    verifySnapshot(of: image, as: .image(precision: 0.98), named: activityName,
                                   file: file, testName: testName, line: line)
                }
                let failure = SnapshotRecording.isEnabled
                    ? withSnapshotTesting(record: .all, operation: verify) : verify()
                if let failure, !SnapshotRecording.isEnabled {
                    XCTFail(failure, file: file, line: line)
                }
            }
        }
    }
}

@MainActor
private func historyAccessibilityLabels(in view: UIView) -> [String] {
    var visited = Set<ObjectIdentifier>()
    var labels: [String] = []
    func visit(_ object: NSObject) {
        guard visited.insert(ObjectIdentifier(object)).inserted else { return }
        if let label = object.accessibilityLabel { labels.append(label) }
        if let view = object as? UIView { view.subviews.forEach(visit) }
        if let elements = object.accessibilityElements {
            elements.compactMap { $0 as? NSObject }.forEach(visit)
        }
        let count = object.accessibilityElementCount()
        if count > 0 && count < 1_000 {
            for index in 0..<count {
                if let element = object.accessibilityElement(at: index) as? NSObject { visit(element) }
            }
        }
    }
    visit(view)
    return labels
}

@MainActor
private final class HistorySnapshotWindow: UIWindow {
    private let snapshotInsets: UIEdgeInsets
    init(size: CGSize, insets: UIEdgeInsets) {
        snapshotInsets = insets
        super.init(frame: CGRect(origin: .zero, size: size))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    override var safeAreaInsets: UIEdgeInsets { snapshotInsets }
}
