import SwiftUI

enum ScanDismissalPolicy {
    static func protect(_ controller: UIViewController) {
        controller.isModalInPresentation = true
    }
}

struct DocumentScannerView: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    let onFailure: (Error) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> DocumentCameraViewController {
        let controller = DocumentCameraViewController()
        controller.delegate = context.coordinator
        ScanDismissalPolicy.protect(controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: DocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, DocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView
        init(parent: DocumentScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: DocumentCameraViewController, didFinishWith pages: [UIImage]) {
            parent.onScan(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: DocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: DocumentCameraViewController, didFailWith error: Error) {
            parent.onFailure(error)
        }
    }
}
