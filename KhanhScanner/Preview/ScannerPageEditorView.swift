import SwiftUI
import UIKit

struct ScannerPageDraft: Identifiable {
    let id: UUID
    var image: UIImage
    var needsEnhancement: Bool

    init(
        id: UUID = UUID(),
        image: UIImage,
        needsEnhancement: Bool
    ) {
        self.id = id
        self.image = image
        self.needsEnhancement = needsEnhancement
    }
}

struct ScannerPageEditorState {
    var pages: [ScannerPageDraft]

    mutating func rotatePage(id: UUID, clockwise: Bool) {
        guard let index = pages.firstIndex(where: { $0.id == id }),
              let rotated = Self.rotated(pages[index].image, clockwise: clockwise) else {
            return
        }
        pages[index].image = rotated
    }

    mutating func deletePage(id: UUID) {
        pages.removeAll { $0.id == id }
    }

    mutating func movePage(id: UUID, offset: Int) {
        guard let source = pages.firstIndex(where: { $0.id == id }) else { return }
        let destination = min(max(0, source + offset), pages.count - 1)
        guard destination != source else { return }
        let page = pages.remove(at: source)
        pages.insert(page, at: destination)
    }

    mutating func cropPage(id: UUID, quadrilateral: ScannerV2Quadrilateral) {
        guard let index = pages.firstIndex(where: { $0.id == id }),
              let cropped = ScannerV2ImageProcessor.manualPerspectiveCrop(
                from: pages[index].image,
                quadrilateral: quadrilateral
              ) else {
            return
        }
        pages[index].image = cropped
    }

    private static func rotated(_ image: UIImage, clockwise: Bool) -> UIImage? {
        let size = CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            if clockwise {
                cg.translateBy(x: size.width, y: 0)
                cg.rotate(by: .pi / 2)
            } else {
                cg.translateBy(x: 0, y: size.height)
                cg.rotate(by: -.pi / 2)
            }
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}

struct ScannerPageEditorView: View {
    @State private var state: ScannerPageEditorState
    @State private var selectedPageID: UUID?
    @State private var croppingPageID: UUID?

    let onCancel: () -> Void
    let onSave: ([ScannerPageDraft]) -> Void

    init(
        pages: [ScannerPageDraft],
        onCancel: @escaping () -> Void,
        onSave: @escaping ([ScannerPageDraft]) -> Void
    ) {
        _state = State(initialValue: ScannerPageEditorState(pages: pages))
        _selectedPageID = State(initialValue: pages.first?.id)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    private var selectedPage: ScannerPageDraft? {
        guard let selectedPageID else { return nil }
        return state.pages.first { $0.id == selectedPageID }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let selectedPage {
                    Image(uiImage: selectedPage.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.04))

                    editorControls(for: selectedPage)
                    thumbnailStrip
                } else {
                    ContentUnavailableView(
                        "No Pages",
                        systemImage: "doc",
                        description: Text("Return to the camera to scan a page.")
                    )
                }
            }
            .padding(.horizontal)
            .navigationTitle("Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Camera") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(state.pages)
                    }
                }
            }
            .sheet(item: croppingBinding) { page in
                ManualPageCropView(image: page.image) { quadrilateral in
                    state.cropPage(id: page.id, quadrilateral: quadrilateral)
                }
            }
        }
    }

    @ViewBuilder
    private func editorControls(for page: ScannerPageDraft) -> some View {
        HStack(spacing: 18) {
            Button {
                state.rotatePage(id: page.id, clockwise: false)
            } label: {
                Label("Left", systemImage: "rotate.left")
            }

            Button {
                croppingPageID = page.id
            } label: {
                Label("Crop", systemImage: "crop")
            }

            Button {
                state.rotatePage(id: page.id, clockwise: true)
            } label: {
                Label("Right", systemImage: "rotate.right")
            }

            Menu {
                Button {
                    state.movePage(id: page.id, offset: -1)
                } label: {
                    Label("Move Earlier", systemImage: "arrow.left")
                }
                .disabled(state.pages.first?.id == page.id)

                Button {
                    state.movePage(id: page.id, offset: 1)
                } label: {
                    Label("Move Later", systemImage: "arrow.right")
                }
                .disabled(state.pages.last?.id == page.id)

                Divider()

                Button(role: .destructive) {
                    delete(page.id)
                } label: {
                    Label("Delete Page", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
            }
        }
        .buttonStyle(.bordered)
    }

    private var thumbnailStrip: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 10) {
                ForEach(Array(state.pages.enumerated()), id: \.element.id) { index, page in
                    Button {
                        selectedPageID = page.id
                    } label: {
                        VStack(spacing: 4) {
                            Image(uiImage: page.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 54, height: 72)
                                .clipped()
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            selectedPageID == page.id ? Color.accentColor : Color.secondary.opacity(0.35),
                                            lineWidth: selectedPageID == page.id ? 3 : 1
                                        )
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text("\(index + 1)")
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(height: 100)
    }

    private var croppingBinding: Binding<ScannerPageDraft?> {
        Binding(
            get: {
                guard let croppingPageID else { return nil }
                return state.pages.first { $0.id == croppingPageID }
            },
            set: { newValue in
                if newValue == nil {
                    croppingPageID = nil
                }
            }
        )
    }

    private func delete(_ id: UUID) {
        guard let index = state.pages.firstIndex(where: { $0.id == id }) else { return }
        state.deletePage(id: id)

        if state.pages.isEmpty {
            selectedPageID = nil
        } else {
            selectedPageID = state.pages[min(index, state.pages.count - 1)].id
        }
    }
}

private struct ManualPageCropView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    let onApply: (ScannerV2Quadrilateral) -> Void

    @State private var quadrilateral = ScannerV2Quadrilateral(
        topLeft: CGPoint(x: 0.02, y: 0.98),
        topRight: CGPoint(x: 0.98, y: 0.98),
        bottomRight: CGPoint(x: 0.98, y: 0.02),
        bottomLeft: CGPoint(x: 0.02, y: 0.02)
    )

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let imageFrame = aspectFitFrame(
                    imageSize: image.size,
                    containerSize: geometry.size
                )

                ZStack {
                    Color.black.ignoresSafeArea()

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: imageFrame.width, height: imageFrame.height)
                        .position(x: imageFrame.midX, y: imageFrame.midY)

                    cropPath(in: imageFrame)
                        .stroke(Color.yellow, lineWidth: 2)

                    handle(
                        for: quadrilateral.topLeft,
                        in: imageFrame,
                        update: { quadrilateral = ScannerV2Quadrilateral(
                            topLeft: $0,
                            topRight: quadrilateral.topRight,
                            bottomRight: quadrilateral.bottomRight,
                            bottomLeft: quadrilateral.bottomLeft
                        )}
                    )
                    handle(
                        for: quadrilateral.topRight,
                        in: imageFrame,
                        update: { quadrilateral = ScannerV2Quadrilateral(
                            topLeft: quadrilateral.topLeft,
                            topRight: $0,
                            bottomRight: quadrilateral.bottomRight,
                            bottomLeft: quadrilateral.bottomLeft
                        )}
                    )
                    handle(
                        for: quadrilateral.bottomRight,
                        in: imageFrame,
                        update: { quadrilateral = ScannerV2Quadrilateral(
                            topLeft: quadrilateral.topLeft,
                            topRight: quadrilateral.topRight,
                            bottomRight: $0,
                            bottomLeft: quadrilateral.bottomLeft
                        )}
                    )
                    handle(
                        for: quadrilateral.bottomLeft,
                        in: imageFrame,
                        update: { quadrilateral = ScannerV2Quadrilateral(
                            topLeft: quadrilateral.topLeft,
                            topRight: quadrilateral.topRight,
                            bottomRight: quadrilateral.bottomRight,
                            bottomLeft: $0
                        )}
                    )
                }
            }
            .navigationTitle("Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(quadrilateral)
                        dismiss()
                    }
                }
            }
        }
    }

    private func cropPath(in frame: CGRect) -> Path {
        var path = Path()
        let points = [
            viewPoint(quadrilateral.topLeft, in: frame),
            viewPoint(quadrilateral.topRight, in: frame),
            viewPoint(quadrilateral.bottomRight, in: frame),
            viewPoint(quadrilateral.bottomLeft, in: frame)
        ]
        guard let first = points.first else { return path }
        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    private func handle(
        for point: CGPoint,
        in frame: CGRect,
        update: @escaping (CGPoint) -> Void
    ) -> some View {
        Circle()
            .fill(Color.yellow)
            .frame(width: 28, height: 28)
            .position(viewPoint(point, in: frame))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        update(normalizedPoint(value.location, in: frame))
                    }
            )
    }

    private func viewPoint(_ point: CGPoint, in frame: CGRect) -> CGPoint {
        CGPoint(
            x: frame.minX + point.x * frame.width,
            y: frame.minY + (1 - point.y) * frame.height
        )
    }

    private func normalizedPoint(_ point: CGPoint, in frame: CGRect) -> CGPoint {
        CGPoint(
            x: min(1, max(0, (point.x - frame.minX) / frame.width)),
            y: min(1, max(0, 1 - (point.y - frame.minY) / frame.height))
        )
    }

    private func aspectFitFrame(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(
            containerSize.width / imageSize.width,
            containerSize.height / imageSize.height
        )
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}
