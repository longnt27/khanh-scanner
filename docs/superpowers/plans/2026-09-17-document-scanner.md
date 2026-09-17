# Document Scanner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native iOS scanner that captures paper documents, enhances readability while preserving colored ink, previews pages, and exports a multi-page PDF.

**Architecture:** SwiftUI owns app state and navigation. VisionKit provides document capture and perspective correction, Core Image performs chroma-aware enhancement, and UIGraphicsPDFRenderer creates A4 PDFs. Native Apple frameworks only.

**Tech Stack:** Swift 5, SwiftUI, VisionKit, CoreImage, UIKit, XCTest, GitHub Actions on macOS/iOS Simulator.

**Spec:** `docs/superpowers/specs/2026-09-17-document-scanner-design.md`

## Global Constraints

- iOS 17.0 minimum deployment target.
- Native Apple frameworks only; no OpenCV or third-party runtime dependencies.
- VisionKit owns capture, edge detection, crop, and perspective correction.
- Enhancement must preserve meaningful chromatic marks such as blue signatures and red stamps.
- Exported pages are A4 and preserve capture order.
- CI is the source of truth for build/test verification because local sandbox access to Xcode is not assumed.

---

### Task 1: Project scaffold and CI

**Files:**
- Create: `KhanhScanner.xcodeproj/project.pbxproj`
- Create: `KhanhScanner/App/KhanhScannerApp.swift`
- Create: `KhanhScanner/App/ContentView.swift`
- Create: `KhanhScanner/Info.plist`
- Create: `KhanhScannerTests/SmokeTests.swift`
- Create: `.github/workflows/ios.yml`

**Interfaces:**
- Produces: an iOS application target named `KhanhScanner` and XCTest target named `KhanhScannerTests`.

- [ ] Create a minimal SwiftUI app and XCTest target.
- [ ] Add camera usage description required by VisionKit.
- [ ] Add CI that resolves an installed iPhone simulator dynamically, builds, then runs tests with code signing disabled.
- [ ] Open a draft PR so subsequent commits receive pull-request CI runs.
- [ ] Verify CI is green.
- [ ] Commit: `chore: scaffold iOS app and CI`.

### Task 2: PDF exporter with TDD

**Files:**
- Create: `KhanhScannerTests/PDFExporterTests.swift`
- Create: `KhanhScanner/PDF/PDFExporter.swift`

**Interfaces:**
- Produces: `enum PDFExporter { static func makePDF(from images: [UIImage]) throws -> Data }`.

- [ ] Write tests proving empty input is rejected, page count equals image count, and mixed portrait/landscape inputs export all pages.
- [ ] Push the tests alone and verify CI fails because `PDFExporter` does not exist.
- [ ] Implement `PDFExporter` with `UIGraphicsPDFRenderer`, per-page A4 portrait/landscape selection, white background, and aspect-fit image drawing.
- [ ] Verify CI is green.
- [ ] Commit: `feat: add A4 PDF exporter`.

### Task 3: Color-preserving document enhancement with TDD

**Files:**
- Create: `KhanhScannerTests/DocumentEnhancerTests.swift`
- Create: `KhanhScanner/Enhancement/DocumentEnhancer.swift`

**Interfaces:**
- Produces: `final class DocumentEnhancer { func enhance(_ image: UIImage) throws -> UIImage }`.

- [ ] Generate deterministic synthetic images in tests with off-white paper, near-black content, saturated blue, and saturated red regions.
- [ ] Assert background luminance rises, dark content stays dark, and red/blue channel dominance plus minimum saturation remain after enhancement.
- [ ] Push tests alone and verify CI fails because `DocumentEnhancer` does not exist.
- [ ] Implement a Core Image color-kernel pipeline that computes luminance/chroma, increases contrast for near-neutral pixels, moderately adjusts colored pixels, and blends by chroma.
- [ ] Normalize orientation and render through a shared `CIContext`.
- [ ] Verify CI is green.
- [ ] Commit: `feat: preserve colored ink during enhancement`.

### Task 4: VisionKit scanner bridge and app state

**Files:**
- Create: `KhanhScanner/Scanner/DocumentScannerView.swift`
- Modify: `KhanhScanner/App/ContentView.swift`

**Interfaces:**
- Produces: `DocumentScannerView(onScan: @escaping ([UIImage]) -> Void, onFailure: @escaping (Error) -> Void, onCancel: @escaping () -> Void)`.

- [ ] Wrap `VNDocumentCameraViewController` in `UIViewControllerRepresentable`.
- [ ] Return captured pages in source order.
- [ ] Enhance pages off the main actor; fall back to original page if enhancement fails.
- [ ] Keep cancellation silent and surface recoverable scan failures in the root view.
- [ ] Verify CI build/tests remain green.
- [ ] Commit: `feat: add VisionKit document capture`.

### Task 5: Preview, export file, and share flow

**Files:**
- Create: `KhanhScanner/Preview/ScanPreviewView.swift`
- Create: `KhanhScanner/PDF/PDFFileWriter.swift`
- Create: `KhanhScanner/Sharing/ShareSheet.swift`
- Modify: `KhanhScanner/App/ContentView.swift`

**Interfaces:**
- Produces: `PDFFileWriter.write(_ data: Data) throws -> URL` and `ShareSheet(items: [Any])`.

- [ ] Add a paged/scrollable preview preserving scan order and showing page count.
- [ ] Generate a fresh temporary `.pdf` URL for every export.
- [ ] Present `UIActivityViewController` with that URL.
- [ ] Preserve preview state and show an error if export fails.
- [ ] Verify CI is green.
- [ ] Commit: `feat: preview and share scanned PDF`.

### Task 6: Final verification and documentation

**Files:**
- Create: `README.md`
- Modify only if verification exposes defects: app/test/workflow files above.

**Interfaces:**
- No new production interface.

- [ ] Run the complete PR CI and inspect job logs for warnings or hidden failures.
- [ ] Confirm tests cover contrast improvement, color preservation, PDF page count, portrait/landscape pages, and empty-input failure.
- [ ] Add concise README usage, architecture, privacy statement, and development instructions.
- [ ] Commit: `docs: add scanner usage and architecture`.
- [ ] Run final CI and inspect changed files before marking the PR ready.
