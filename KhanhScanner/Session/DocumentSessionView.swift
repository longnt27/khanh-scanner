import SwiftUI

struct DocumentSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: DocumentLibrary
    let sessionID: UUID
    let onScan: () -> Void

    @State private var pageDrafts: [ScannerPageDraft] = []
    @State private var shareURL: URL?
    @State private var showingShare = false
    @State private var showingExportConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var showingRenameDocument = false
    @State private var showingPageEditor = false
    @State private var editingPageID: UUID?
    @State private var renameDocumentText = ""
    @State private var errorMessage: String?

    private var session: DocumentSession? { library.session(id: sessionID) }
    private var pages: [UIImage] { pageDrafts.map(\.renderedImage) }

    var body: some View {
        Group {
            if let session {
                if pages.isEmpty {
                    ContentUnavailableView(
                        "No Pages Yet",
                        systemImage: "doc.viewfinder",
                        description: Text("Scan pages now or return later. This document is already saved.")
                    )
                } else {
                    ScanPreviewView(
                        documentName: session.name,
                        pages: pages,
                        onTapPage: { index in
                            guard pageDrafts.indices.contains(index) else { return }
                            editingPageID = pageDrafts[index].id
                            showingPageEditor = true
                        },
                        onAddPages: onScan,
                        onExport: exportPDF
                    )
                }
            } else {
                ContentUnavailableView("Document Not Found", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle(session?.name ?? "Document")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if session != nil, pages.isEmpty {
                Button(action: onScan) {
                    Label("Scan Pages", systemImage: "camera.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.top, 8)
                .background(.bar)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        beginRenaming()
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Document", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Document actions")
                .disabled(session == nil)
            }
        }
        .task(id: session?.modifiedAt) { loadPages() }
        .sheet(isPresented: $showingShare) {
            if let shareURL {
                ShareSheet(items: [shareURL], onCompletion: handleExportCompletion)
            }
        }
        .fullScreenCover(isPresented: $showingPageEditor) {
            ScannerPageEditorView(
                pages: pageDrafts,
                initialPageID: editingPageID,
                onCancel: {
                    showingPageEditor = false
                    editingPageID = nil
                },
                onDone: saveEditedPages
            )
        }
        .confirmationDialog(
            "Delete this document and all of its pages?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Document", role: .destructive, action: deleteSession)
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Document", isPresented: $showingRenameDocument) {
            TextField("Document name", text: $renameDocumentText)
            Button("Save", action: renameDocument)
            Button("Cancel", role: .cancel) {}
        }
        .alert("Khanh Scanner", isPresented: errorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .alert("PDF exported", isPresented: $showingExportConfirmation) {
            Button("Done") { dismiss() }
        } message: {
            Text("The PDF was saved successfully. Your document remains available here.")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func loadPages() {
        do {
            pageDrafts = try library.pageAssets(for: sessionID).map {
                ScannerPageDraft(assets: $0)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveEditedPages(_ drafts: [ScannerPageDraft]) {
        do {
            let existingIDs = Set(session?.pageIDs ?? [])
            let finalIDs = drafts.map(\.id)
            let finalSet = Set(finalIDs)

            for pageID in existingIDs.subtracting(finalSet) {
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
            showingPageEditor = false
            editingPageID = nil
            loadPages()
        } catch {
            errorMessage = "Could not save page edits: \(error.localizedDescription)"
        }
    }

    private func exportPDF() {
        guard let session else { return }
        do {
            shareURL = try PDFFileWriter.write(
                PDFExporter.makePDF(from: pages),
                suggestedName: session.name
            )
            showingShare = true
        } catch {
            errorMessage = "Could not create PDF: \(error.localizedDescription)"
        }
    }

    private func handleExportCompletion(_ completed: Bool) {
        showingShare = false
        if let shareURL {
            try? FileManager.default.removeItem(at: shareURL.deletingLastPathComponent())
            self.shareURL = nil
        }
        guard completed else { return }
        DispatchQueue.main.async {
            showingExportConfirmation = true
        }
    }

    private func beginRenaming() {
        guard let session else { return }
        renameDocumentText = session.name
        showingRenameDocument = true
    }

    private func renameDocument() {
        do {
            try library.renameSession(id: sessionID, to: renameDocumentText)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSession() {
        do {
            try library.deleteSession(id: sessionID)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}
