import SwiftUI
import UIKit
import VisionKit

/// SwiftUI wrapper over the system document scanner. The scanner's edge detection and
/// perspective correction produce a clean, de-skewed page image, which materially
/// improves downstream text recognition versus a raw camera frame.
struct DocumentScannerView: UIViewControllerRepresentable {
    enum Outcome {
        case scanned(UIImage)
        case cancelled
        case failed(Error)
    }

    var onFinish: (Outcome) -> Void

    /// The document scanner needs a camera, so it is unavailable in the Simulator.
    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onFinish: (Outcome) -> Void

        init(onFinish: @escaping (Outcome) -> Void) {
            self.onFinish = onFinish
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            guard scan.pageCount > 0 else {
                onFinish(.cancelled)
                return
            }
            onFinish(.scanned(scan.imageOfPage(at: 0)))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish(.cancelled)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            onFinish(.failed(error))
        }
    }
}
