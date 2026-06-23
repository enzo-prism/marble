import XCTest

final class ScanFlowUITests: MarbleUITestCase {
    /// The handwritten-workout scan flow is reachable from the Import hub and its capture
    /// screen renders. (The camera button depends on device support and the OCR/parse step
    /// needs a real image, so this smoke test verifies reachability + that the capture UI
    /// renders without crashing; the parse/import logic is covered by unit tests.)
    func testOpenScanFromImportHub() {
        launchApp(fixtureMode: "populated")
        navigateToTab(.journal)

        let importButton = app.buttons["Journal.ImportWorkouts"]
        waitFor(importButton)
        importButton.tap()

        let scanOpen = waitForIdentifier("Import.Scan.Open", timeout: 8)
        scanOpen.tap()

        // The scan capture screen renders and is reachable.
        let capture = waitForIdentifier("Scan.Capture", timeout: 5)
        XCTAssertTrue(capture.exists, "Scan capture screen should render")

        // The photo-picker entry point always renders (camera depends on device support).
        let choosePhoto = waitForIdentifier("Scan.ChoosePhoto", timeout: 5)
        XCTAssertTrue(choosePhoto.exists, "Choose Photo should be available")

        takeScreenshot("Scan_CaptureScreen")

        // Dismiss back to the import hub.
        let dismiss = waitForIdentifier("Scan.Dismiss", timeout: 3)
        dismiss.tap()
        let scanReopen = waitForIdentifier("Import.Scan.Open", timeout: 5)
        XCTAssertTrue(scanReopen.exists, "Should return to the import hub")
    }
}
