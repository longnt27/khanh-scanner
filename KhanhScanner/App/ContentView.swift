import SwiftUI
import VisionKit

struct ContentView: View {
    @StateObject private var library = DocumentLibrary()
    @State private var path: [LibraryRoute] = []
    @State private var scanningSessionID: UUID?
    @State private var showingScanner = false
    @State private var errorMessage: String?
    @State private var rejectedPageCount: Int?
    @State private var isProcessing = false

    var body: some View {
        NavigationStack(path: $path) {
            LibraryBrowserView(
                library: library,
                currentFolderID: nil,
                canScan: !isProcessing && VNDocumentCameraViewController.isSupported,
                onNewDocument: newDocument
            )
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case let .session(sessionID):
                    DocumentSessionView(library: library, sessionID: sessionID) {
                        beginScanning(sessionID: sessionID)
                    }
                case let .folder(folderID):
                    LibraryBrowserView(
                        library: library,
                        currentFolderID: folderID,
                        canScan: !isProcessing && VNDocumentCameraViewController.isSupported,
                        onNewDocument: newDocument
                    )
                }
            }
            .overlay {
                if isProcessing {
                    ProgressView("Saving pages…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .fullScreenCover(isPresented: $showingScanner) {
            DocumentScannerView(onScan: { captured in
                showingScanner = false
                process(captured, for: scanningSessionID)
            }, onRejected: { count in
                showingScanner = false
                rejectedPageCount = count
            }, onFailure: { error in
                showingScanner = false
                errorMessage = error.localizedDescription
            }, onCancel: {
                showingScanner = false
            })
            .interactiveDismissDisabled()
        }
        .alert("Khanh Scanner", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .alert("Page Not Saved", isPresented: Binding(
            get: { rejectedPageCount != nil },
            set: { if !$0 { rejectedPageCount = nil } }
        )) {
            Button("Scan Again") {
                rejectedPageCount = nil
                if let scanningSessionID {
                    beginScanning(sessionID: scanningSessionID)
                }
            }
            Button("Later", role: .cancel) {
                rejectedPageCount = nil
            }
        } message: {
            Text(rejectionMessage)
        }
    }

    private func newDocument(in folderID: UUID?) {
        do {
            let session = try library.createSession(in: folderID)
            path.append(.session(session.id))
            beginScanning(sessionID: session.id)
        } catch {
            errorMessage = "Could not create document: \(error.localizedDescription)"
        }
    }

    private func beginScanning(sessionID: UUID) {
        scanningSessionID = sessionID
        showingScanner = true
    }

    private var rejectionMessage: String {
        let count = rejectedPageCount ?? 1
        let pageDescription = count == 1 ? "That page was" : "Those \(count) pages were"
        return "\(ScannedPageQualityValidator.warningMessage) \(pageDescription) not saved."
    }

    private func process(_ captured: [UIImage], for sessionID: UUID?) {
        guard let sessionID else { return }
        isProcessing = true
        Task.detached(priority: .userInitiated) {
            let enhancer = DocumentEnhancer()
            let enhanced = captured.map { image in (try? enhancer.enhance(image)) ?? image }
            await MainActor.run {
                do {
                    try library.appendPages(enhanced, to: sessionID)
                } catch {
                    errorMessage = "Could not save pages: \(error.localizedDescription)"
                }
                isProcessing = false
            }
        }
    }
}

#Preview { ContentView() }
