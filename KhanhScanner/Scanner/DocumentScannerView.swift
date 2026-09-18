import SwiftUI
import VisionKit

enum ScanDismissalPolicy {
    static func protect(_ controller: UIViewController) {
        controller.isModalInPresentation = true
    }
}

struct DocumentScannerView: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    let onRejected: (Int) -> Void
    let onFailure: (Error) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        ScanDismissalPolicy.protect(controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView

        init(parent: DocumentScannerView) {
            self.parent = parent
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            DispatchQueue.global(qos: .userInitiated).async { [parent] in
                let validation = ScannedPageQualityValidator.validate(pages)
                DispatchQueue.main.async {
                    controller.dismiss(animated: true) {
                        if !validation.acceptedPages.isEmpty {
                            parent.onScan(validation.acceptedPages)
                        }
                        if validation.rejectedPageCount > 0 {
                            parent.onRejected(validation.rejectedPageCount)
                        }
                    }
                }
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true) { [parent] in
                parent.onCancel()
            }
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            controller.dismiss(animated: true) { [parent] in
                parent.onFailure(error)
            }
        }
    }
}
