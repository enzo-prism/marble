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
        let detailList = app.tables.firstMatch.exists ? app.tables.firstMatch : app.collectionViews.firstMatch

        let editCropButton = app.buttons["Calendar.ProgressMedia.EditCrop"]
        scrollToElement(editCropButton, in: detailList)
        forceTap(editCropButton)

        let cropEditor = app.navigationBars["Edit Crop"]
        waitFor(cropEditor, timeout: 8)
        let cropSave = app.buttons["Calendar.ProgressMedia.Crop.Save"]
        waitFor(cropSave, timeout: 8)
        let cropSaveCoordinate = cropSave.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        )
        forceTap(app.buttons["Calendar.ProgressMedia.Crop.Reset"])
        // iOS 26.5 can briefly return an empty automation snapshot immediately
        // after Reset updates the gesture-backed crop canvas. The toolbar does
        // not move, so retain its already-verified coordinate for this tap.
        cropSaveCoordinate.tap()
        waitForDisappearance(cropEditor, timeout: 8)

        let deleteButton = app.buttons["Calendar.ProgressMedia.Delete"]
        scrollToElement(deleteButton, in: detailList)
        waitFor(deleteButton, timeout: 8)

        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        forceTap(backButton)
        waitForIdentifier("Calendar.DaySheet.List", timeout: 8)

        dismissSheet()
    }
}
