import SnapshotTesting
import SwiftUI
import XCTest
@testable import marble

/// The widget snapshot suite the 2.2 roadmap asked for and build 48 shipped
/// without: before this, the five Weekly Goal families had **no** automated
/// coverage of any kind, so a layout regression in the app's only external
/// surface could only be caught by installing the widget by hand.
///
/// Framed at real widget point sizes rather than through `SnapshotMatrix`
/// (whose device frames would stretch a 170×170 card across a phone screen), and
/// each family is snapshotted both with a live snapshot and in its "nothing
/// trustworthy to show" state — the neutral card is the state a fresh install
/// actually sees first.
@MainActor
final class WeeklyGoalWidgetSnapshotTests: SnapshotTestCase {
    // Point sizes for a modern iPhone. Approximate on purpose: the value here
    // is catching layout breakage (clipped copy, overflowing rings) at widget
    // scale, not matching one device pixel-for-pixel.
    private enum WidgetSize {
        static let small = CGSize(width: 170, height: 170)
        static let medium = CGSize(width: 364, height: 170)
        static let circular = CGSize(width: 76, height: 76)
        static let rectangular = CGSize(width: 172, height: 76)
        static let inline = CGSize(width: 250, height: 26)
    }

    /// Fixed dates so the state is renderable and the images are deterministic.
    private var state: WeeklyGoalWidgetState {
        WeeklyGoalWidgetState(
            target: 3,
            thisWeekSessions: 2,
            streakWeeks: 4,
            flexTokens: 1,
            stateRaw: "inProgress",
            weekStart: WeeklyGoalWidgetState.startOfWeek(for: SnapshotFixtures.now),
            generatedAt: SnapshotFixtures.now
        )
    }

    /// The at-risk wording plus a longer streak line — the copy most likely to
    /// clip in the accessory families.
    private var atRiskState: WeeklyGoalWidgetState {
        WeeklyGoalWidgetState(
            target: 6,
            thisWeekSessions: 1,
            streakWeeks: 12,
            flexTokens: 3,
            stateRaw: "atRisk",
            weekStart: WeeklyGoalWidgetState.startOfWeek(for: SnapshotFixtures.now),
            generatedAt: SnapshotFixtures.now
        )
    }

    // MARK: - Home Screen

    func testWeeklyGoalSmall() {
        assertWidgetSnapshot(WeeklyGoalSmallView(state: state), size: WidgetSize.small, named: "WeeklyGoalSmall")
    }

    func testWeeklyGoalSmallEmpty() {
        assertWidgetSnapshot(WeeklyGoalSmallView(state: nil), size: WidgetSize.small, named: "WeeklyGoalSmallEmpty")
    }

    func testWeeklyGoalMedium() {
        assertWidgetSnapshot(WeeklyGoalMediumView(state: state), size: WidgetSize.medium, named: "WeeklyGoalMedium")
    }

    func testWeeklyGoalMediumAtRisk() {
        assertWidgetSnapshot(WeeklyGoalMediumView(state: atRiskState), size: WidgetSize.medium, named: "WeeklyGoalMediumAtRisk")
    }

    // MARK: - Lock Screen

    func testWeeklyGoalAccessoryCircular() {
        assertWidgetSnapshot(WeeklyGoalCircularView(state: state), size: WidgetSize.circular, named: "WeeklyGoalCircular")
    }

    func testWeeklyGoalAccessoryCircularEmpty() {
        assertWidgetSnapshot(WeeklyGoalCircularView(state: nil), size: WidgetSize.circular, named: "WeeklyGoalCircularEmpty")
    }

    func testWeeklyGoalAccessoryRectangular() {
        assertWidgetSnapshot(WeeklyGoalRectangularView(state: atRiskState), size: WidgetSize.rectangular, named: "WeeklyGoalRectangular")
    }

    func testWeeklyGoalAccessoryRectangularEmpty() {
        assertWidgetSnapshot(WeeklyGoalRectangularView(state: nil), size: WidgetSize.rectangular, named: "WeeklyGoalRectangularEmpty")
    }

    func testWeeklyGoalAccessoryInline() {
        assertWidgetSnapshot(WeeklyGoalInlineView(state: state), size: WidgetSize.inline, named: "WeeklyGoalInline")
    }

    // MARK: - Harness

    private func assertWidgetSnapshot<V: View>(
        _ view: V,
        size: CGSize,
        named name: String,
        // `#filePath`, not `#file`: under the Swift 6 language mode `#file` is the
    // *concise* "Module/File.swift" form, which sent SnapshotTesting looking for
    // baselines at `/MarbleSnapshotTests/__Snapshots__/…` — a read-only volume.
    file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            let activityName = "\(name)_\(suffix)"
            XCTContext.runActivity(named: activityName) { _ in
                autoreleasepool {
                    let configured = view
                        .environment(\.colorScheme, scheme)
                        .transaction { $0.disablesAnimations = true }
                        .padding(8)
                        .frame(width: size.width, height: size.height)
                        .background(scheme == .dark ? Color.black : Color.white)

                    let traits = UITraitCollection(traitsFrom: [
                        UITraitCollection(userInterfaceIdiom: .phone),
                        UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
                    ])

                    let failure = verifySnapshot(
                        of: configured,
                        as: .image(
                            precision: 0.98,
                            layout: .fixed(width: size.width, height: size.height),
                            traits: traits
                        ),
                        named: activityName,
                        file: file,
                        testName: testName,
                        line: line
                    )

                    if let failure, !SnapshotRecording.isEnabled {
                        XCTFail(failure, file: file, line: line)
                    }
                }
            }
        }
    }
}
