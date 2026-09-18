import SwiftUI

struct DocumentSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: DocumentLibrary
    let sessionID: UUID
    let onScan: () -> Void

    @State private var pages: [UIImage] = []
    @State private var shareURL: URL?
    @State private var showingShare = false
    @State private var showingExportConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var showingRenameDocument = false
    @State private var renameDocumentText = ""
    @State private var errorMessage: String?

    private var session: DocumentSession? { library.session(id: sessionID) }

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
                        pages: pages,
                        onExport: exportPDF,
                        onRescan: onScan,
                        rescanTitle: "Add Pages"
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    beginRenaming()
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Rename document")
                .disabled(session == nil)

                Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete document")
                .disabled(session == nil)
            }
        }
        .task(id: session?.modifiedAt) { loadPages() }
        .sheet(isPresented: $showingShare) {
            if let shareURL {
                ShareSheet(items: [shareURL], onCompletion: handleExportCompletion)
            }
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
            pages = try library.images(for: sessionID)
        } catch {
            errorMessage = error.localizedDescription
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
