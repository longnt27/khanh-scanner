import SwiftUI

struct ScanPreviewView: View {
    let documentName: String
    let pages: [UIImage]
    let onTapPage: (Int) -> Void
    let onAddPages: () -> Void
    let onExport: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("\(pages.count) page\(pages.count == 1 ? "" : "s")")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 16) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        Button {
                            onTapPage(index)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Image(uiImage: page)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 310, maxHeight: 520)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .shadow(radius: 2)

                                Text("Page \(index + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit page \(index + 1)")
                    }
                }
                .padding()
            }

            VStack(spacing: 10) {
                Button(action: onAddPages) {
                    Label("Add Pages", systemImage: "camera.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onExport) {
                    Label("Export PDF", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .navigationTitle(documentName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
