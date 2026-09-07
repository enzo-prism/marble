import XCTest
import UIKit
@testable import marble

@MainActor
final class ProgressOverviewQuotesTests: XCTestCase {
    func testFiltersByRenderedWidthAndPreservesSessionOrder() {
        let font = ProgressOverviewQuotes.font(pointSize: 12)
        let short = quote("short", "Keep going.")
        let long = quote("long", "A very long quote that cannot fit within this narrow overview footer.")
        let other = quote("other", "Begin.")
        let result = ProgressOverviewQuotes.fitting([short, long, other], width: 100, font: font)
        XCTAssertEqual(result, [short, other])
    }

    func testRejectsExplicitLineBreaksAndInvalidWidths() {
        let quotes = [quote("one", "Go."), quote("two", "Go.\nNow."), quote("empty", "")]
        let font = ProgressOverviewQuotes.font(pointSize: 12)
        XCTAssertEqual(ProgressOverviewQuotes.fitting(quotes, width: 300, font: font).map(\.id), ["one"])
        for width: CGFloat in [0, -1, .nan, .infinity] {
            XCTAssertTrue(ProgressOverviewQuotes.fitting(quotes, width: width, font: font).isEmpty)
        }
    }

    func testDynamicTypeAndBoldTextOnlyAllowCompleteFittingQuotes() {
        for size: CGFloat in [12, 20, 40, 60] {
            for bold in [false, true] {
                let font = ProgressOverviewQuotes.font(pointSize: size, bold: bold)
                for width: CGFloat in [250, 327, 500] {
                    let result = ProgressOverviewQuotes.fitting(DailyHighlightQuoteLibrary.all, width: width, font: font)
                    for quote in result {
                        XCTAssertLessThanOrEqual(ceil((quote.text as NSString).size(withAttributes: [.font: font]).width) + 2, width)
                    }
                }
            }
        }
        XCTAssertFalse(ProgressOverviewQuotes.fitting(DailyHighlightQuoteLibrary.all, width: 250, font: ProgressOverviewQuotes.font(pointSize: 12)).isEmpty)
        XCTAssertTrue(ProgressOverviewQuotes.fitting(DailyHighlightQuoteLibrary.all, width: 3, font: ProgressOverviewQuotes.font(pointSize: 60)).isEmpty)
    }

    private func quote(_ id: String, _ text: String) -> DailyHighlightQuote {
        DailyHighlightQuote(id: id, text: text, author: "Author", source: "Source", sourceURL: "https://example.com")
    }
}
