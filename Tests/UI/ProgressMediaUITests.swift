import XCTest

final class ProgressMediaUITests: MarbleUITestCase {
    func testProgressMediaCanAttachPhotoAndVideoToCalendarDay() {
        launchApp(fixtureMode: "populated", calendarTestDay: "populated")
        navigateToTab(.calendar)

        let daySheetQuery = app.descendants(matching: .any).matching(identifier: "Calendar.DaySheet.List").firstMatch
        if !daySheetQuery.waitForExistence(timeout: 5) {
            selectCalendarDay("15")
        }
        let daySheetList = waitForIdentifier("Calendar.DaySheet.List", timeout: 8)

        let addPhoto = app.buttons["Calendar.ProgressMedia.AddTestPhoto"]
        scrollToElement(addPhoto, in: daySheetList)
        forceTap(addPhoto)

        let photoItem = waitForIdentifier("Calendar.ProgressMedia.Item.photo", timeout: 8)
        XCTAssertTrue(photoItem.label.localizedCaseInsensitiveContains("progress photo"))

        let addVideo = app.buttons["Calendar.ProgressMedia.AddTestVideo"]
        scrollToElement(addVideo, in: daySheetList)
        forceTap(addVideo)

        let videoItem = waitForIdentifier("Calendar.ProgressMedia.Item.video", timeout: 8)
        XCTAssertTrue(videoItem.label.localizedCaseInsensitiveContains("progress video"))

        let summary = waitForIdentifier("Calendar.ProgressMedia.Summary", timeout: 8)
        XCTAssertTrue(summary.label.contains("2 progress items"))

        forceTap(photoItem)
        waitForIdentifier("Calendar.ProgressMedia.Detail", timeout: 8)
        let deleteButton = app.buttons["Calendar.ProgressMedia.Delete"]
        let detailList = app.tables.firstMatch.exists ? app.tables.firstMatch : app.collectionViews.firstMatch
        scrollToElement(deleteButton, in: detailList)
        waitFor(deleteButton, timeout: 8)

        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        forceTap(backButton)
        waitForIdentifier("Calendar.DaySheet.List", timeout: 8)

        dismissSheet()
    }
}
