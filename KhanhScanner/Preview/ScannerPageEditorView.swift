import SwiftUI
import UIKit

struct ScannerPageDraft: Identifiable {
    let id: UUID
    var sourceImage: UIImage
    var cropQuadrilateral: ScannerV2Quadrilateral
    var rotation: DocumentPageRotation
    var renderedImage: UIImage
    var needsEnhancement: Bool
    var isLegacySource: Bool
    var isPersisted: Bool
    var isDirty: Bool

    var image: UIImage { renderedImage }

    var documentPage: DocumentPage {
        DocumentPage(
            id: id,
            cropQuadrilateral: cropQuadrilateral,
            rotation: rotation,
            isLegacySource: isLegacySource
        )
    }

    init(
        id: UUID = UUID(),
        image: UIImage,
        needsEnhancement: Bool
    ) {
        self.id = id
        sourceImage = image
        cropQuadrilateral = .fullBounds
        rotation = .none
        renderedImage = image
        self.needsEnhancement = needsEnhancement
        isLegacySource = true
        isPersisted = false
        isDirty = true
    }

    init(
        id: UUID = UUID(),
        sourceImage: UIImage,
        cropQuadrilateral: ScannerV2Quadrilateral,
        rotation: DocumentPageRotation = .none,
        renderedImage: UIImage,
        needsEnhancement: Bool,
        isLegacySource: Bool,
        isPersisted: Bool = false,
        isDirty: Bool = true
    ) {
        self.id = id
        self.sourceImage = sourceImage
        self.cropQuadrilateral = cropQuadrilateral
        self.rotation = rotation
        self.renderedImage = renderedImage
        self.needsEnhancement = needsEnhancement
        self.isLegacySource = isLegacySource
        self.isPersisted = isPersisted
        self.isDirty = isDirty
    }

    init(assets: DocumentPageAssets) {
        id = assets.page.id
        sourceImage = assets.sourceImage
        cropQuadrilateral = assets.page.cropQuadrilateral
        rotation = assets.page.rotation
        renderedImage = assets.renderedImage
        needsEnhancement = false
        isLegacySource = assets.page.isLegacySource
        isPersisted = true
        isDirty = false
    }

    var shouldEnhanceWhileEditing: Bool {
        !isLegacySource && !needsEnhancement
    }
}

struct ScannerPageEditorState {
    var pages: [ScannerPageDraft]

    mutating func rotatePage(id: UUID, clockwise: Bool) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }

        var updated = pages[index]
        updated.rotation = updated.rotation.rotated(clockwise: clockwise)
        guard let rendered = try? DocumentPageRenderer.render(
            source: updated.sourceImage,
            page: updated.documentPage,
            enhance: updated.shouldEnhanceWhileEditing
        ) else {
            return
        }

        updated.renderedImage = rendered
        updated.isDirty = true
        pages[index] = updated
    }

    mutating func deletePage(id: UUID) {
        pages.removeAll { $0.id == id }
    }

    mutating func movePage(id: UUID, offset: Int) {
        guard let source = pages.firstIndex(where: { $0.id == id }),
              !pages.isEmpty else {
            return
        }
        let destination = min(max(0, source + offset), pages.count - 1)
        guard destination != source else { return }
        let page = pages.remove(at: source)
        pages.insert(page, at: destination)
    }

    @discardableResult
    mutating func cropPage(
        id: UUID,
        quadrilateral: ScannerV2Quadrilateral
    ) -> Bool {
        guard quadrilateral.isValidCrop,
              let index = pages.firstIndex(where: { $0.id == id }) else {
            return false
        }

        var updated = pages[index]
        updated.cropQuadrilateral = quadrilateral
        guard let rendered = try? DocumentPageRenderer.render(
            source: updated.sourceImage,
            page: updated.documentPage,
            enhance: updated.shouldEnhanceWhileEditing
        ) else {
            return false
        }

        updated.renderedImage = rendered
        updated.isDirty = true
        pages[index] = updated
        return true
    }
}

struct ScannerPageEditorView: View {
    @State private var state: ScannerPageEditorState
    @State private var selectedPageID: UUID?
    @State private var croppingPageID: UUID?
    @State private var errorMessage: String?

    let onCancel: () -> Void
    let onDone: ([ScannerPageDraft]) -> Void

    init(
        pages: [ScannerPageDraft],
        initialPageID: UUID? = nil,
        onCancel: @escaping () -> Void,
        onDone: @escaping ([ScannerPageDraft]) -> Void
    ) {
        _state = State(initialValue: ScannerPageEditorState(pages: pages))
        let selected = initialPageID.flatMap { requested in
            pages.contains(where: { $0.id == requested }) ? requested : nil
        } ?? pages.first?.id
        _selectedPageID = State(initialValue: selected)
        self.onCancel = onCancel
        self.onDone = onDone
    }

    private var selectedPage: ScannerPageDraft? {
        guard let selectedPageID else { return nil }
        return state.pages.first { $0.id == selectedPageID }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let selectedPage {
                    Image(uiImage: selectedPage.renderedImage)
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
                        description: Text("There are no pages in this document.")
                    )
                }
            }
            .padding(.horizontal)
            .navigationTitle("Edit Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(state.pages)
                    }
                }
            }
            .sheet(item: croppingBinding) { page in
                ManualPageCropView(
                    image: page.sourceImage,
                    quadrilateral: page.cropQuadrilateral
                ) { quadrilateral in
                    if !state.cropPage(id: page.id, quadrilateral: quadrilateral) {
                        errorMessage = "That crop shape cannot be rendered."
                    }
                }
            }
            .alert(
                "Could Not Edit Page",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
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
                            Image(uiImage: page.renderedImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 54, height: 72)
                                .clipped()
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            selectedPageID == page.id
                                                ? Color.accentColor
                                                : Color.secondary.opacity(0.35),
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

    @State private var quadrilateral: ScannerV2Quadrilateral
    @State private var activePoint: CGPoint?

    init(
        image: UIImage,
        quadrilateral: ScannerV2Quadrilateral,
        onApply: @escaping (ScannerV2Quadrilateral) -> Void
    ) {
        self.image = image
        self.onApply = onApply
        _quadrilateral = State(initialValue: quadrilateral)
    }

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
                        update: {
                            quadrilateral = ScannerV2Quadrilateral(
                                topLeft: $0,
                                topRight: quadrilateral.topRight,
                                bottomRight: quadrilateral.bottomRight,
                                bottomLeft: quadrilateral.bottomLeft
                            )
                        }
                    )
                    handle(
                        for: quadrilateral.topRight,
                        in: imageFrame,
                        update: {
                            quadrilateral = ScannerV2Quadrilateral(
                                topLeft: quadrilateral.topLeft,
                                topRight: $0,
                                bottomRight: quadrilateral.bottomRight,
                                bottomLeft: quadrilateral.bottomLeft
                            )
                        }
                    )
                    handle(
                        for: quadrilateral.bottomRight,
                        in: imageFrame,
                        update: {
                            quadrilateral = ScannerV2Quadrilateral(
                                topLeft: quadrilateral.topLeft,
                                topRight: quadrilateral.topRight,
                                bottomRight: $0,
                                bottomLeft: quadrilateral.bottomLeft
                            )
                        }
                    )
                    handle(
                        for: quadrilateral.bottomLeft,
                        in: imageFrame,
                        update: {
                            quadrilateral = ScannerV2Quadrilateral(
                                topLeft: quadrilateral.topLeft,
                                topRight: quadrilateral.topRight,
                                bottomRight: quadrilateral.bottomRight,
                                bottomLeft: $0
                            )
                        }
                    )

                    if let activePoint,
                       let magnified = magnifiedImage(at: activePoint) {
                        VStack {
                            ZStack {
                                Image(uiImage: magnified)
                                    .resizable()
                                    .scaledToFill()
                                Rectangle()
                                    .fill(Color.yellow)
                                    .frame(width: 1, height: 86)
                                Rectangle()
                                    .fill(Color.yellow)
                                    .frame(width: 86, height: 1)
                            }
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white, lineWidth: 3))
                            .shadow(radius: 4)
                            Spacer()
                        }
                        .padding(.top, 18)
                    }
                }
            }
            .navigationTitle("Adjust Corners")
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
                    .disabled(!quadrilateral.isValidCrop)
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
        ZStack {
            Circle()
                .fill(Color.yellow)
                .frame(width: 24, height: 24)
            Circle()
                .fill(Color.clear)
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .position(viewPoint(point, in: frame))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let normalized = normalizedPoint(value.location, in: frame)
                    activePoint = normalized
                    update(normalized)
                }
                .onEnded { _ in
                    activePoint = nil
                }
        )
    }

    private func magnifiedImage(at point: CGPoint) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let center = CGPoint(
            x: point.x * width,
            y: (1 - point.y) * height
        )
        let side = max(40, min(width, height) * 0.12)
        var crop = CGRect(
            x: center.x - side / 2,
            y: center.y - side / 2,
            width: side,
            height: side
        )
        crop.origin.x = min(max(0, crop.origin.x), max(0, width - side))
        crop.origin.y = min(max(0, crop.origin.y), max(0, height - side))

        guard let cropped = cgImage.cropping(to: crop.integral) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
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
