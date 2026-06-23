import CoreGraphics
import CryptoKit
import Foundation
import Vision

/// Reads text out of a captured image. Abstracted so the scan view model can be
/// driven by a stub in tests without touching the Vision framework.
protocol WorkoutTextRecognizing: Sendable {
    func recognizeText(in image: CGImage) async throws -> String
}

/// On-device OCR via the Vision framework. Tuned for accuracy with language
/// correction, which also covers handwriting on supported devices. Everything stays
/// on device — no network, consistent with Marble's local-only privacy posture.
nonisolated struct VisionWorkoutTextRecognizer: WorkoutTextRecognizing {
    func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                    let observations = request.results ?? []
                    let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                    continuation.resume(returning: lines.joined(separator: "\n"))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// Stable content identity for a captured image, used as the scan's dedup key so
/// importing the identical photo twice is a no-op.
nonisolated enum WorkoutScanImageHash {
    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
