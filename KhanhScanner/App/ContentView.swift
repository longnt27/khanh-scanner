import SwiftUI

struct ContentView: View {
    @StateObject private var library = DocumentLibrary()
    @State private var path: [LibraryRoute] = []
    @State private var scanningSessionID: UUID?
    @State private var scannerInitialPages: [UIImage] = []
    @State private var showingScanner = false
    @State private var errorMessage: String?
    @State private var isProcessing = false

    var body: some View {
        NavigationStack(path: $path) {
            LibraryBrowserView(
                library: library,
                currentFolderID: nil,
                canScan: !isProcessing && DocumentScannerView.isSupported,
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
                        canScan: !isProcessing && DocumentScannerView.isSupported,
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
            DocumentScannerView(initialPages: scannerInitialPages, onScan: { drafts in
                showingScanner = false
                process(drafts, for: scanningSessionID)
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
        do {
            scannerInitialPages = try library.images(for: sessionID)
            scanningSessionID = sessionID
            showingScanner = true
        } catch {
            errorMessage = "Could not open document pages: \(error.localizedDescription)"
        }
    }

    private func process(_ drafts: [ScannerPageDraft], for sessionID: UUID?) {
        guard let sessionID else { return }
        isProcessing = true
        Task.detached(priority: .userInitiated) {
            let enhancer = DocumentEnhancer()
            let finalPages = drafts.map { draft in
                guard draft.needsEnhancement else { return draft.image }
                return (try? enhancer.enhance(draft.image)) ?? draft.image
            }

            await MainActor.run {
                do {
                    try library.replacePages(finalPages, in: sessionID)
                } catch {
                    errorMessage = "Could not save pages: \(error.localizedDescription)"
                }
                scannerInitialPages = []
                isProcessing = false
            }
        }
    }
}

#Preview { ContentView() }
