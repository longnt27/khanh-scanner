# Khanh Scanner — Document Scanner Design

## Goal
Build a native iOS app that turns photographed paper documents into clean multi-page PDFs. The scanner must detect and rectify the page, make paper look white and printed text look black, while preserving meaningful colors such as blue signatures, red stamps, and highlights.

## Scope

### Included in the MVP
- Native iOS app using SwiftUI.
- Document capture using VisionKit document scanning.
- Automatic page edge detection and perspective correction through VisionKit.
- Multi-page scan sessions.
- Post-processing that increases document readability while preserving chromatic ink.
- Page preview after scanning.
- PDF generation from processed pages.
- System share/export flow.
- Unit tests for image enhancement and PDF generation.
- GitHub Actions workflow that builds and tests on an iOS Simulator.

### Explicitly excluded from the MVP
- OCR or searchable PDFs.
- Cloud sync, accounts, storage backends, or analytics.
- Custom camera capture UI.
- OpenCV or third-party image-processing dependencies.
- Manual crop-handle editing after capture.

## Architecture

### App shell
SwiftUI owns navigation and state. The first screen starts a scan. A completed VisionKit scan produces an ordered array of page images. Those images are processed and shown in a preview. Export creates one PDF from the processed pages and opens the system share sheet.

### Document capture
`DocumentScannerView` wraps `VNDocumentCameraViewController` with `UIViewControllerRepresentable`.

Responsibilities:
- Present VisionKit's scanner UI.
- Return all captured pages in order.
- Surface cancel and scan failures without crashing the app.

VisionKit is responsible for camera capture, document rectangle detection, crop, and perspective correction. The app does not duplicate that work in the MVP.

### Image enhancement
`DocumentEnhancer` accepts a `UIImage` and returns an enhanced `UIImage`.

The enhancement pipeline must:
1. Normalize image orientation.
2. Estimate local/global paper luminance using Core Image primitives.
3. Increase luminance contrast so light neutral areas move toward white and dark neutral areas move toward black.
4. Preserve chromatic pixels instead of desaturating the whole page.
5. Apply only moderate luminance/contrast adjustment to sufficiently saturated pixels so blue ink, red stamps, colored highlights, and similar marks remain colored.

The implementation must not use a blanket grayscale filter because that would destroy exactly the information the app is required to preserve.

A practical MVP implementation may use a Core Image color kernel that derives luminance and chroma per pixel, creates a high-contrast neutral result, then blends between the neutral result and a contrast-adjusted color result based on chroma magnitude. This keeps the algorithm deterministic and unit-testable.

### Preview
`ScanPreviewView` displays the processed pages in capture order with page count and a primary Export PDF action. Individual page deletion/reordering is excluded from the first MVP unless it falls out trivially from the chosen state model.

### PDF export
`PDFExporter` converts an ordered `[UIImage]` into PDF data.

Rules:
- One scanned image becomes one PDF page.
- Use standard A4 dimensions in points.
- Choose portrait or landscape independently for each page based on source aspect ratio.
- Aspect-fit the image within the page bounds without distortion.
- White-fill any unused page area.
- Preserve source ordering.

### Sharing
The app writes generated PDF data to a temporary file with a `.pdf` extension and presents `UIActivityViewController` via a SwiftUI wrapper.

## Primary data flow

1. User launches the app.
2. User taps Scan Document.
3. VisionKit captures one or more pages and applies its document crop/perspective correction.
4. The app receives `[UIImage]`.
5. `DocumentEnhancer` processes each image off the main thread.
6. The processed images are displayed in `ScanPreviewView`.
7. User taps Export PDF.
8. `PDFExporter` generates PDF data and writes it to a temporary file.
9. The system share sheet opens with the PDF file.

## Error handling

- VisionKit cancellation returns to the initial screen without an error banner.
- VisionKit failures show a short recoverable error message and allow scanning again.
- Enhancement failure for one page falls back to that captured page rather than dropping the page.
- PDF creation failure keeps the preview intact and presents an error instead of dismissing user work.
- Temporary export files are recreated per export so stale files are not reused accidentally.

## Testing strategy

### Image enhancement tests
Generate deterministic synthetic fixtures in code rather than depending on camera photos in CI.

Fixtures should contain:
- Off-white or light gray paper background.
- Near-black text/rectangles.
- A saturated blue mark.
- A saturated red mark.

Assertions should verify:
- Background luminance increases.
- Black content remains dark or becomes darker.
- Red and blue regions retain significant saturation.
- Red and blue regions retain their dominant hue/channel relationship after processing.

Tests should use tolerances rather than exact pixel equality because Core Image rendering can vary slightly across OS versions and GPU/CPU execution paths.

### PDF tests
Verify:
- Non-empty PDF data is produced.
- PDF page count equals input image count.
- Mixed portrait/landscape input still produces all pages.

### CI
GitHub Actions runs on a macOS runner and uses an available iOS Simulator destination. The workflow must build the app and run unit tests on pushes and pull requests.

## Project structure

- `KhanhScanner/App/` — app entry point and root navigation/state.
- `KhanhScanner/Scanner/` — VisionKit bridge and scan result types.
- `KhanhScanner/Enhancement/` — document image enhancement implementation.
- `KhanhScanner/Preview/` — processed-page preview and export UI.
- `KhanhScanner/PDF/` — PDF creation and temporary file export.
- `KhanhScanner/Sharing/` — share sheet wrapper.
- `KhanhScannerTests/` — image enhancement and PDF tests.
- `.github/workflows/ios.yml` — iOS build/test workflow.

## Technology constraints

- Swift and SwiftUI.
- Native Apple frameworks only for the MVP.
- VisionKit for scanning.
- Core Image for image processing.
- UIKit/Core Graphics or UIGraphicsPDFRenderer for PDF creation and UIKit sharing.
- No OpenCV or third-party image-processing dependency.

## Definition of done

The MVP is complete when a user can scan multiple paper pages on an iPhone, see corrected/enhanced pages, export them as one PDF, and share that PDF; synthetic tests demonstrate that paper/text contrast improves while blue/red marks stay colored; and GitHub Actions successfully builds and runs tests on an iOS Simulator.
