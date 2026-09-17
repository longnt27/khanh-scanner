# Khanh Scanner

A native iOS document scanner that turns photographed paper into clean multi-page PDFs without throwing away useful color.

## What it does

- Uses Apple's VisionKit scanner for automatic document detection, cropping, and perspective correction.
- Enhances neutral paper/text contrast with Core Image.
- Preserves colored ink such as blue signatures and red stamps.
- Previews all captured pages in order.
- Exports portrait and landscape pages to an A4 PDF.
- Shares the generated PDF with the standard iOS share sheet.
- Processes scans locally on the device. There is no account, cloud backend, analytics SDK, or third-party image-processing dependency.

## Run it

1. Clone the repository.
2. Open `KhanhScanner.xcodeproj` in Xcode 16 or newer.
3. Select the `KhanhScanner` scheme and an iPhone running iOS 17 or newer.
4. Run the app and grant camera access.
5. Tap **Scan Document**, capture one or more pages, finish the VisionKit scan, inspect the enhanced preview, then tap **Export PDF**.

The document camera is hardware-dependent, so the actual capture flow should be exercised on a physical iPhone. Build and unit tests run in GitHub Actions on an iOS Simulator.

## Architecture

`Scanner/` bridges `VNDocumentCameraViewController`. `Enhancement/` contains the chroma-aware Core Image pipeline. `PDF/` creates A4 PDF data and fresh temporary files. `Preview/` and `Sharing/` provide the user-facing preview/export flow. Tests generate synthetic images so CI can verify contrast and color preservation deterministically.

## Privacy

Captured pages and generated PDFs stay on device unless the user explicitly chooses a destination in the system share sheet.
