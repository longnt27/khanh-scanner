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
                } else {
                    ScanPreviewView(
                        pages: pages,
                        onExport: exportPDF,
                        onRescan: session.lifecycle == .active ? onScan : resumeScan,
                        rescanTitle: session.lifecycle == .active ? "Add Pages" : "Resume Scan"
                    )
                }
            } else {
                ContentUnavailableView("Document Not Found", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle(session.map(title) ?? "Document")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let session {
                VStack(spacing: 10) {
                    if pages.isEmpty {
                        Button(action: session.lifecycle == .active ? onScan : resumeScan) {
                            Label(
                                session.lifecycle == .active ? "Scan Pages" : "Resume Scan",
                                systemImage: "camera.viewfinder"
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if session.lifecycle == .active {
                        Button(action: finishSession) {
                            Label("Done", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .background(.bar)
            }
        }
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

    private func finishSession() {
        do {
            try library.setLifecycle(.archived, for: sessionID)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resumeScan() {
        do {
            try library.setLifecycle(.active, for: sessionID)
            onScan()
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

    private func title(for session: DocumentSession) -> String {
        session.createdAt.formatted(date: .abbreviated, time: .shortened)
    }
}
