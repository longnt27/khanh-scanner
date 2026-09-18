import ARKit
import SwiftUI
import VisionKit

enum ScanDismissalPolicy {
    static func protect(_ controller: UIViewController) {
        controller.isModalInPresentation = true
    }
}

struct DocumentScannerView: UIViewControllerRepresentable {
    static var isSupported: Bool {
        ScannerV2ViewController.isSupported || VNDocumentCameraViewController.isSupported
    }

    let initialPages: [ScannerPageDraft]
    let onScan: ([ScannerPageDraft]) -> Void
    let onFailure: (Error) -> Void
    let onCancel: () -> Void

    init(
        initialPages: [ScannerPageDraft] = [],
        onScan: @escaping ([ScannerPageDraft]) -> Void,
        onFailure: @escaping (Error) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialPages = initialPages
        self.onScan = onScan
        self.onFailure = onFailure
        self.onCancel = onCancel
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIViewController {
        if ScannerV2ViewController.isSupported {
            let controller = ScannerV2ViewController(initialPages: initialPages)
            controller.delegate = context.coordinator
            ScanDismissalPolicy.protect(controller)
            return controller
        }

        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        ScanDismissalPolicy.protect(controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate, ScannerV2ViewControllerDelegate {
        let parent: DocumentScannerView

        init(parent: DocumentScannerView) {
            self.parent = parent
        }

        func scannerV2ViewController(
            _ controller: ScannerV2ViewController,
            didFinishWith pages: [ScannerPageDraft]
        ) {
            parent.onScan(pages)
        }

        func scannerV2ViewControllerDidCancel(_ controller: ScannerV2ViewController) {
            parent.onCancel()
        }

        func scannerV2ViewController(
            _ controller: ScannerV2ViewController,
            didFailWith error: Error
        ) {
            parent.onFailure(error)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let existing = parent.initialPages
            let captured = (0..<scan.pageCount).map {
                ScannerPageDraft(
                    image: scan.imageOfPage(at: $0),
                    needsEnhancement: true
                )
            }
            controller.dismiss(animated: true) { [parent] in
                parent.onScan(existing + captured)
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
