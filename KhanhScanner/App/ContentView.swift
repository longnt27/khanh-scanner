import SwiftUI
import VisionKit

struct ContentView: View {
    @State private var pages: [UIImage] = []
    @State private var showingScanner = false
    @State private var shareURL: URL?
    @State private var errorMessage: String?
    @State private var isProcessing = false

    var body: some View {
        NavigationStack {
            Group {
                if pages.isEmpty {
                    VStack(spacing: 22) {
                        Image(systemName: "doc.viewfinder")
                            .font(.system(size: 72))
                            .foregroundStyle(.tint)
                        Text("Khanh Scanner").font(.largeTitle.bold())
                        Text("Clean paper scans. Black text. Colored signatures and stamps stay colored.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button {
                            showingScanner = true
                        } label: {
                            Label("Scan Document", systemImage: "camera.viewfinder")
                                .font(.headline)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isProcessing || !VNDocumentCameraViewController.isSupported)

                        if !VNDocumentCameraViewController.isSupported {
                            Text("Document scanning requires a supported iPhone or iPad.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if isProcessing { ProgressView("Enhancing pages…") }
                    }
                    .padding(28)
                } else {
                    ScanPreviewView(pages: pages, onExport: exportPDF, onRescan: { showingScanner = true })
                }
            }
        }
        .sheet(isPresented: $showingScanner) {
            DocumentScannerView(onScan: process, onFailure: { error in
                errorMessage = error.localizedDescription
            }, onCancel: {})
        }
        .sheet(item: $shareURL) { url in
            ShareSheet(items: [url])
        }
        .alert("Khanh Scanner", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func process(_ captured: [UIImage]) {
        isProcessing = true
        Task.detached(priority: .userInitiated) {
            let enhancer = DocumentEnhancer()
            let enhanced = captured.map { image in (try? enhancer.enhance(image)) ?? image }
            await MainActor.run {
                pages = enhanced
                isProcessing = false
            }
        }
    }

    private func exportPDF() {
        do {
            shareURL = try PDFFileWriter.write(PDFExporter.makePDF(from: pages))
        } catch {
            errorMessage = "Could not create PDF: \(error.localizedDescription)"
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

#Preview { ContentView() }
