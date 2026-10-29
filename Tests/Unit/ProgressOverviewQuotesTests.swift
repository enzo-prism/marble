import XCTest
import UIKit
import SwiftUI
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

    func testAll25AthleteQuotesFitANarrowPhoneAtDefaultCaptionSize() {
        // Use rendered glyph widths, not character counts: long wide-letter
        // quotes must not quietly enter a catalog that never displays on a phone.
        XCTAssertEqual(AthleteQuotes.quotes.count, 25)
        for bold in [false, true] {
            let font = ProgressOverviewQuotes.font(pointSize: 12, bold: bold)
            let fitting = ProgressOverviewQuotes.fitting(AthleteQuotes.quotes, width: 250, font: font)
            XCTAssertEqual(fitting.map(\.id), AthleteQuotes.quotes.map(\.id))
        }
    }

    func testAthleteQuotesBecomeIneligibleInsteadOfShrinkingWhenTextGrows() {
        let font = ProgressOverviewQuotes.font(pointSize: 40, bold: true)
        let fitting = ProgressOverviewQuotes.fitting(AthleteQuotes.quotes, width: 250, font: font)
        XCTAssertLessThan(fitting.count, AthleteQuotes.quotes.count)
        for quote in fitting {
            XCTAssertLessThanOrEqual(ceil((quote.text as NSString).size(withAttributes: [.font: font]).width) + 2, 250)
        }
        // Widening the layout recovers quotes in their original session order.
        XCTAssertEqual(
            ProgressOverviewQuotes.fitting(AthleteQuotes.quotes, width: 2_000, font: font),
            AthleteQuotes.quotes
        )
    }

    func testBothRotatorStylesHideAPoolThatCannotFit() {
        let tooWide = quote("too-wide", String(repeating: "Wide quote ", count: 20))
        for centered in [false, true] {
            let hidden = UIHostingController(rootView: DailyHighlightQuoteRotator(
                day: Date(timeIntervalSince1970: 0),
                centered: centered,
                quotePool: [tooWide],
                availableWidth: 100
            ))
            let visible = UIHostingController(rootView: DailyHighlightQuoteRotator(
                day: Date(timeIntervalSince1970: 0),
                centered: centered,
                quotePool: [quote("fits", "Go.")],
                availableWidth: 100
            ))
            let proposal = CGSize(width: 100, height: 1_000)
            XCTAssertEqual(hidden.sizeThatFits(in: proposal).height, 0)
            XCTAssertGreaterThanOrEqual(visible.sizeThatFits(in: proposal).height, 44)
        }
    }

    private func quote(_ id: String, _ text: String) -> DailyHighlightQuote {
        DailyHighlightQuote(id: id, text: text, author: "Author", source: "Source", sourceURL: "https://example.com")
    }
}
