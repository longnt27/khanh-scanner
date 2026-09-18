import SwiftUI
import UIKit

enum ShareCompletionPolicy {
    static func isSuccessful(completed: Bool, error: Error?) -> Bool {
        completed && error == nil
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let onCompletion: (Bool) -> Void

    init(items: [Any], onCompletion: @escaping (Bool) -> Void = { _ in }) {
        self.items = items
        self.onCompletion = onCompletion
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            let success = ShareCompletionPolicy.isSuccessful(completed: completed, error: error)
            DispatchQueue.main.async {
                context.coordinator.onCompletion(success)
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    final class Coordinator {
        let onCompletion: (Bool) -> Void

        init(onCompletion: @escaping (Bool) -> Void) {
            self.onCompletion = onCompletion
        }
    }
}
