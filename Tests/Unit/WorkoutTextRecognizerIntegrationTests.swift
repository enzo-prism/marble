import XCTest
import UIKit
@testable import marble

/// Exercises the REAL Vision text recognizer (not a mock) on a rendered image, proving the
/// on-device OCR step of the handwritten-scan pipeline actually extracts text. The parser is
/// covered separately with mocked OCR text in `HandwrittenWorkoutParserTests`.
final class WorkoutTextRecognizerIntegrationTests: XCTestCase {
    func testVisionRecognizesRenderedWorkoutText() async throws {
        let image = Self.renderLines(["BENCH PRESS", "100 x 5", "SQUAT 225 x 3"])
        guard let cgImage = image.cgImage else {
            return XCTFail("Could not build a CGImage to recognize")
        }

        let recognizer = VisionWorkoutTextRecognizer()
        let text = try await recognizer.recognizeText(in: cgImage)

        // Robust, OCR-variance-tolerant assertions: Vision reliably reads clear printed
        // text, so we assert it produced non-empty output that includes the numeric content.
        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "Vision should extract some text; got empty output")
        XCTAssertTrue(text.contains(where: { $0.isNumber }),
                      "Vision should read the numbers in the workout; got: \(text)")
    }

    private static func renderLines(_ lines: [String]) -> UIImage {
        let size = CGSize(width: 700, height: 420)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 46, weight: .semibold),
                .foregroundColor: UIColor.black
            ]
            var y: CGFloat = 30
            for line in lines {
                (line as NSString).draw(at: CGPoint(x: 36, y: y), withAttributes: attributes)
                y += 110
            }
        }
    }
}
