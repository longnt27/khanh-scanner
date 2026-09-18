import SwiftUI

struct ContentView: View {
    @StateObject private var library = DocumentLibrary()
    @State private var path: [LibraryRoute] = []
    @State private var scanningSessionID: UUID?
    @State private var scannerInitialPages: [ScannerPageDraft] = []
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
            scannerInitialPages = try library.pageAssets(for: sessionID).map {
                ScannerPageDraft(assets: $0)
            }
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
            let finalized = drafts.map { draft -> ScannerPageDraft in
                guard draft.needsEnhancement else { return draft }

                var updated = draft
                updated.renderedImage =
                    (try? enhancer.enhance(draft.renderedImage)) ?? draft.renderedImage
                updated.needsEnhancement = false
                updated.isDirty = true
                return updated
            }

            await MainActor.run {
                do {
                    try persist(finalized, in: sessionID)
                } catch {
                    errorMessage = "Could not save pages: \(error.localizedDescription)"
                }
                scannerInitialPages = []
                isProcessing = false
            }
        }
    }

    private func persist(_ drafts: [ScannerPageDraft], in sessionID: UUID) throws {
        let existingIDs = Set(library.session(id: sessionID)?.pageIDs ?? [])
        let finalIDs = drafts.map(\.id)
        let finalIDSet = Set(finalIDs)

        for pageID in existingIDs.subtracting(finalIDSet) {
            try library.deletePage(id: pageID, from: sessionID)
        }

        let newAssets = drafts
            .filter { !existingIDs.contains($0.id) }
            .map {
                DocumentPageAssets(
                    page: $0.documentPage,
                    sourceImage: $0.sourceImage,
                    renderedImage: $0.renderedImage
                )
            }
        if !newAssets.isEmpty {
            try library.appendPageRecords(newAssets, to: sessionID)
        }

        for draft in drafts where existingIDs.contains(draft.id) && draft.isDirty {
            try library.updatePage(
                draft.documentPage,
                in: sessionID,
                renderedImage: draft.renderedImage
            )
        }

        try library.reorderPages(finalIDs, in: sessionID)
    }
}

#Preview { ContentView() }
