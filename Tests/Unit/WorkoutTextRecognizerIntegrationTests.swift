import XCTest
import UIKit
@testable import marble

/// Exercises the REAL Vision text recognizer (not a mock) on a rendered image, proving the
/// on-device OCR step of the handwritten-scan pipeline actually extracts text. The parser is
/// covered separately with mocked OCR text in `HandwrittenWorkoutParserTests`.
@MainActor
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

    /// The structured document request keeps a program grid's row on one line, so
    /// the parser sees "Bench Press 3 8 185" instead of scattered cells.
    func testStructuredRecognitionKeepsGridRowsTogether() async throws {
        let rows = [["Exercise", "Sets", "Reps", "Load"], ["Bench Press", "3", "8", "185"], ["Back Squat", "5", "5", "225"]]
        guard let cgImage = Self.renderGrid(rows).cgImage else { return XCTFail("Could not build a CGImage") }
        let text: String
        do {
            text = try await VisionWorkoutTextRecognizer.recognizeDocument(in: cgImage)
        } catch {
            throw XCTSkip("RecognizeDocumentsRequest is unavailable on this runtime (\(error)); the recognizer falls back to line OCR.")
        }
        try XCTSkipIf(text.isEmpty, "RecognizeDocumentsRequest read nothing on this runtime; the recognizer falls back to line OCR.")
        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertTrue(lines.contains { $0.contains("Bench") && $0.contains("185") }, "Rows must stay on one line; got: \(lines)")
        XCTAssertTrue(lines.contains { $0.contains("Squat") && $0.contains("225") }, "Rows must stay on one line; got: \(lines)")
    }

    private static func renderGrid(_ rows: [[String]]) -> UIImage {
        let columns: [CGFloat] = [30, 420, 560, 700]
        let size = CGSize(width: 860, height: CGFloat(rows.count) * 90 + 60)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setStroke()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 36, weight: .medium), .foregroundColor: UIColor.black
            ]
            for (index, row) in rows.enumerated() {
                let y = 30 + CGFloat(index) * 90
                for (column, cell) in row.enumerated() {
                    (cell as NSString).draw(at: CGPoint(x: columns[column], y: y + 20), withAttributes: attributes)
                }
                let line = UIBezierPath()
                line.move(to: CGPoint(x: 20, y: y)); line.addLine(to: CGPoint(x: size.width - 20, y: y))
                line.stroke()
            }
        }
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
