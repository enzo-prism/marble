import CoreGraphics
import XCTest
@testable import marble

/// The structured-OCR line assembly, without Vision: tables keep one line per row,
/// paragraphs keep reading order, and nothing is read twice.
final class DocumentTextLayoutTests: XCTestCase {
    private typealias Layout = DocumentTextLayout

    /// Normalized rect with Vision's lower-left origin; `top` is the upper edge.
    private func rect(top: CGFloat, height: CGFloat, x: CGFloat = 0.1, width: CGFloat = 0.8) -> CGRect {
        CGRect(x: x, y: top - height, width: width, height: height)
    }

    func testTableEmitsOneLinePerRowInColumnOrder() {
        let cells: [Layout.Cell] = [
            .init(row: 1, column: 2, text: "8"),
            .init(row: 0, column: 0, text: "Exercise"),
            .init(row: 1, column: 0, text: "Bench Press"),
            .init(row: 0, column: 2, text: "Reps"),
            .init(row: 1, column: 1, text: "3"),
            .init(row: 0, column: 1, text: "Sets"),
            .init(row: 1, column: 3, text: "185 lb"),
            .init(row: 2, column: 0, text: "Back\nSquat"),
            .init(row: 2, column: 3, text: "225"),
            .init(row: 2, column: 1, text: "5"),
            .init(row: 2, column: 2, text: "5"),
        ]
        XCTAssertEqual(Layout.tableRows(cells), [
            "Exercise Sets Reps",
            "Bench Press 3 8 185 lb",
            "Back Squat 5 5 225",
        ])
    }

    func testSpanningAndEmptyCellsAreNotRepeatedOrPadded() {
        // Vision reports a row-spanning cell in every row it covers.
        let cells: [Layout.Cell] = [
            .init(row: 0, column: 0, text: "Deadlift"),
            .init(row: 0, column: 1, text: "315 x 5"),
            .init(row: 0, column: 0, text: "Deadlift"),
            .init(row: 1, column: 1, text: "335 x 3"),
            .init(row: 1, column: 2, text: "  "),
            .init(row: 2, column: 0, text: ""),
        ]
        XCTAssertEqual(Layout.tableRows(cells), ["Deadlift 315 x 5", "335 x 3"])
    }

    func testParagraphsKeepReadingOrderAndTablesSlotInByPosition() {
        let blocks: [Layout.Block] = [
            .init(content: .text(["Push Day", "Week 3"]), bounds: rect(top: 0.95, height: 0.08)),
            .init(content: .text(["Finish with 10 min bike"]), bounds: rect(top: 0.3, height: 0.05)),
            .init(content: .table([
                .init(row: 0, column: 0, text: "Bench"), .init(row: 0, column: 1, text: "3x8"),
                .init(row: 1, column: 0, text: "Dips"), .init(row: 1, column: 1, text: "3x10"),
            ]), bounds: rect(top: 0.8, height: 0.4)),
        ]
        XCTAssertEqual(Layout.lines(from: blocks), [
            "Push Day", "Week 3", "Bench 3x8", "Dips 3x10", "Finish with 10 min bike",
        ])
    }

    func testParagraphInsideATableIsReadOnlyOnceAsTableRows() {
        let tableBounds = rect(top: 0.8, height: 0.4)
        let blocks: [Layout.Block] = [
            // Vision may also report the table's text as a paragraph.
            .init(content: .text(["Bench", "3x8", "Dips", "3x10"]), bounds: tableBounds.insetBy(dx: 0.01, dy: 0.01)),
            .init(content: .table([
                .init(row: 0, column: 0, text: "Bench"), .init(row: 0, column: 1, text: "3x8"),
                .init(row: 1, column: 0, text: "Dips"), .init(row: 1, column: 1, text: "3x10"),
            ]), bounds: tableBounds),
        ]
        XCTAssertEqual(Layout.lines(from: blocks), ["Bench 3x8", "Dips 3x10"])
    }

    func testListItemsAreLinesAndADuplicateTitleIsDropped() {
        let titleBounds = rect(top: 0.95, height: 0.05)
        let blocks: [Layout.Block] = [
            .init(content: .text(["Leg Day"]), bounds: titleBounds),
            .init(content: .text(["Leg Day"]), bounds: titleBounds),
            .init(content: .list(["Squat 5x5 225", " Lunges  3x12 "]), bounds: rect(top: 0.85, height: 0.2)),
        ]
        XCTAssertEqual(Layout.lines(from: blocks), ["Leg Day", "Squat 5x5 225", "Lunges 3x12"])
    }

    func testStructuredBlocksWithoutParagraphsAreKept() {
        let blocks: [Layout.Block] = [
            .init(content: .list(["Row 3x10"]), bounds: rect(top: 0.4, height: 0.1)),
            .init(content: .table([.init(row: 0, column: 0, text: "Squat 5x5")]), bounds: rect(top: 0.9, height: 0.1)),
        ]
        XCTAssertEqual(Layout.lines(from: blocks), ["Squat 5x5", "Row 3x10"])
        XCTAssertEqual(Layout.lines(from: []), [])
    }
}
