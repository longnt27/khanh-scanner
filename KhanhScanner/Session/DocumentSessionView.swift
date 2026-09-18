import SwiftUI

struct DocumentSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: DocumentLibrary
    let sessionID: UUID
    let onScan: () -> Void

    @State private var pages: [UIImage] = []
    @State private var shareURL: URL?
    @State private var showingShare = false
    @State private var showingDeleteConfirmation = false
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
                    .overlay(alignment: .bottom) {
                        scanButton.padding()
                    }
                } else {
                    ScanPreviewView(pages: pages, onExport: exportPDF, onRescan: onScan)
                }
            } else {
                ContentUnavailableView("Document Not Found", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle(session.map(title) ?? "Document")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete document")
                .disabled(session == nil)
            }
        }
        .task(id: session?.modifiedAt) { loadPages() }
        .sheet(isPresented: $showingShare) {
            if let shareURL { ShareSheet(items: [shareURL]) }
        }
        .confirmationDialog(
            "Delete this document and all of its pages?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Document", role: .destructive, action: deleteSession)
            Button("Cancel", role: .cancel) {}
        }
        .alert("Khanh Scanner", isPresented: errorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var scanButton: some View {
        Button(action: onScan) {
            Label("Scan Pages", systemImage: "camera.viewfinder")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
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
        do {
            shareURL = try PDFFileWriter.write(PDFExporter.makePDF(from: pages))
            showingShare = true
        } catch {
            errorMessage = "Could not create PDF: \(error.localizedDescription)"
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

    private func title(for session: DocumentSession) -> String {
        session.createdAt.formatted(date: .abbreviated, time: .shortened)
    }
}
