import SwiftUI
import VisionKit

struct ContentView: View {
    @StateObject private var library = DocumentLibrary()
    @State private var path: [UUID] = []
    @State private var scanningSessionID: UUID?
    @State private var showingScanner = false
    @State private var errorMessage: String?
    @State private var isProcessing = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if library.sessions.isEmpty {
                    ContentUnavailableView(
                        "No Documents",
                        systemImage: "doc.viewfinder",
                        description: Text("Start a scan. It will be saved before the camera opens.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(library.sessions) { session in
                        NavigationLink(value: session.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.headline)
                                Text(
                                    "\(session.pageIDs.count) page\(session.pageIDs.count == 1 ? "" : "s") · "
                                    + (session.lifecycle == .active ? "In Progress" : "Finished")
                                )
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Khanh Scanner")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: newDocument) {
                        Label("New Document Scan", systemImage: "plus")
                    }
                    .disabled(isProcessing || !VNDocumentCameraViewController.isSupported)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if library.sessions.isEmpty {
                    Button(action: newDocument) {
                        Label("New Document Scan", systemImage: "camera.viewfinder")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                    .disabled(isProcessing || !VNDocumentCameraViewController.isSupported)
                }
            }
            .overlay {
                if isProcessing {
                    ProgressView("Saving pages…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationDestination(for: UUID.self) { sessionID in
                DocumentSessionView(library: library, sessionID: sessionID) {
                    beginScanning(sessionID: sessionID)
                }
            }
        }
        .fullScreenCover(isPresented: $showingScanner) {
            DocumentScannerView(onScan: { captured in
                showingScanner = false
                process(captured, for: scanningSessionID)
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

    private func newDocument() {
        do {
            let session = try library.createSession()
            path.append(session.id)
            beginScanning(sessionID: session.id)
        } catch {
            errorMessage = "Could not create document: \(error.localizedDescription)"
        }
    }

    private func beginScanning(sessionID: UUID) {
        scanningSessionID = sessionID
        showingScanner = true
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
