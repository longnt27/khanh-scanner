import SwiftUI

struct ScanPreviewView: View {
    let pages: [UIImage]
    let onExport: () -> Void
    let onRescan: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("\(pages.count) page\(pages.count == 1 ? "" : "s")")
                    .font(.headline)
                Spacer()
                Button("Scan Again", action: onRescan)
            }
            .padding(.horizontal)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 16) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        VStack(alignment: .leading, spacing: 6) {
                            Image(uiImage: page)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 310, maxHeight: 520)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .shadow(radius: 2)
                            Text("Page \(index + 1)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }

            Button(action: onExport) {
                Label("Export PDF", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .navigationTitle("Preview")
    }
}
