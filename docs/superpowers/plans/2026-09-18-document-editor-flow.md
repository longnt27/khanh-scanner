# Document Editor Flow Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current page-preview/editor flow with a document-centric workflow that preserves raw captures, supports true four-corner recropping, and uses consistent scanner/editor navigation.

**Architecture:** Persist each page as an editable record backed by a source image, crop quadrilateral, rotation metadata, and rendered image. Scanner V2 creates page records from the full-resolution camera frame before perspective correction. The repository owns page asset persistence and rendering updates; the preview/editor consumes page records and commits page-scoped mutations without rewriting unrelated pages.

**Tech Stack:** Swift 5, SwiftUI, UIKit, ARKit, Vision, Core Image, XCTest, iOS 17+.

**Spec:** `docs/superpowers/specs/2026-09-18-document-editor-flow-design.md`

## Global Constraints

- iOS deployment target remains 17.0.
- Scanner V2 stays the preferred capture path; VisionKit remains only the unsupported-device fallback.
- Existing PNG-only documents must continue to load without eager migration.
- Manual crop must operate on the original source image for new Scanner V2 pages.
- Existing legacy pages may only crop within the pixels that still exist.
- Scanner editor Back resumes camera; Scanner editor Done finishes scanner and returns to the document preview.
- Document preview uses the document name as its title.
- Rename and Delete live in a single overflow menu.
- Add Pages is a full-width primary action directly above Export PDF.

---

### Task 1: Persist editable page records

**Files:**
- Create: `KhanhScanner/Persistence/DocumentPage.swift`
- Modify: `KhanhScanner/Persistence/DocumentSession.swift`
- Modify: `KhanhScanner/Persistence/DocumentSessionRepository.swift`
- Modify: `KhanhScanner/Persistence/DocumentLibrary.swift`
- Modify: `KhanhScanner.xcodeproj/project.pbxproj`
- Test: `KhanhScannerTests/DocumentSessionRepositoryTests.swift`

**Interfaces:**
- Produces: `DocumentPage`, `DocumentPageRotation`, `DocumentPageAssets`
- Produces repository APIs:
  - `pageRecords(for sessionID: UUID) throws -> [DocumentPage]`
  - `appendPageRecords(_:to:modifiedAt:) throws -> DocumentSession`
  - `updatePage(_:in:renderedImage:modifiedAt:) throws`
  - `deletePage(id:from:modifiedAt:) throws`
  - `reorderPages(_:in:modifiedAt:) throws`
  - `sourceImage(for:in:) throws -> UIImage`
  - `renderedImage(for:in:) throws -> UIImage`

- [ ] **Step 1: Write failing persistence tests**

Add tests that create a page record with a source image and rendered image, reload the repository, and verify the crop quadrilateral and rotation survive. Add a legacy test that writes the old PNG-only layout and verifies the repository synthesizes a full-bounds crop record.

- [ ] **Step 2: Run CI and verify RED**

Expected failure: `DocumentPage` and page-record repository APIs do not exist.

- [ ] **Step 3: Add the page model**

Create a Codable `DocumentPage` with:

```swift
struct DocumentPage: Codable, Identifiable, Equatable {
    let id: UUID
    var cropQuadrilateral: ScannerV2Quadrilateral
    var rotation: DocumentPageRotation
    var isLegacySource: Bool
}
```

Add Codable conformance to `ScannerV2Quadrilateral` and define quarter-turn rotation metadata.

- [ ] **Step 4: Add page-aware asset persistence**

Store new pages under:

```
Pages/<session-id>/<page-id>/source.jpg
Pages/<session-id>/<page-id>/rendered.png
Pages/<session-id>/<page-id>/metadata.json
```

Keep reading old `Pages/<session-id>/<page-id>.png` files as legacy page records with full-bounds crop and zero rotation. Do not rewrite them until an edit requires it.

- [ ] **Step 5: Expose page APIs through DocumentLibrary**

Wrap repository page-record load/update/delete/reorder methods and reload session state after mutations.

- [ ] **Step 6: Run tests and commit**

Expected: persistence tests and existing repository tests pass.

Commit:

```
feat: persist editable document pages
```

### Task 2: Render pages from source + crop + rotation

**Files:**
- Create: `KhanhScanner/Preview/DocumentPageRenderer.swift`
- Modify: `KhanhScanner/ScannerV2/ScannerV2ImageProcessor.swift`
- Modify: `KhanhScanner.xcodeproj/project.pbxproj`
- Test: `KhanhScannerTests/ScannerV2GeometryTests.swift`

**Interfaces:**
- Consumes: `DocumentPage`, source `UIImage`
- Produces:
  - `DocumentPageRenderer.render(source:page:enhance:) throws -> UIImage`
  - `ScannerV2Quadrilateral.isValidCrop`

- [ ] **Step 1: Write failing renderer tests**

Test that a non-full-bounds quadrilateral changes perspective from the original source, rotation happens after crop, a full-bounds crop preserves a legacy image, and invalid/self-intersecting quadrilaterals are rejected.

- [ ] **Step 2: Run CI and verify RED**

Expected failure: renderer and crop validation APIs do not exist.

- [ ] **Step 3: Implement crop validation**

Reject self-intersecting shapes, near-zero area, duplicated corners, and points outside normalized source bounds.

- [ ] **Step 4: Implement rendering**

Render in this order:

```
source
-> perspective correction
-> conservative border cleanup
-> quarter-turn rotation
-> DocumentEnhancer when enhance == true
```

- [ ] **Step 5: Run tests and commit**

Commit:

```
feat: render editable pages from source geometry
```

### Task 3: Capture and retain the real source image

**Files:**
- Modify: `KhanhScanner/Preview/ScannerPageEditorView.swift`
- Modify: `KhanhScanner/ScannerV2/ScannerV2ViewController.swift`
- Modify: `KhanhScanner/Scanner/DocumentScannerView.swift`
- Modify: `KhanhScanner/App/ContentView.swift`
- Test: `KhanhScannerTests/ScannerV2GeometryTests.swift`

**Interfaces:**
- Replace image-only `ScannerPageDraft` with:
  - `id`
  - `sourceImage`
  - `cropQuadrilateral`
  - `rotation`
  - `renderedImage`
  - `needsEnhancement`
  - `isLegacySource`
- Scanner V2 completion returns full editable drafts.

- [ ] **Step 1: Write failing draft/capture tests**

Verify a draft rendered from a crop still retains a larger source image and the original detected quadrilateral.

- [ ] **Step 2: Run CI and verify RED**

Expected failure: new draft fields do not exist.

- [ ] **Step 3: Capture the oriented high-resolution source**

Create the oriented `UIImage` directly from the high-resolution AR frame before perspective correction. Store Vision's high-resolution document quadrilateral alongside it.

- [ ] **Step 4: Render preview from the draft source**

Use `DocumentPageRenderer` for the displayed/rendered page rather than discarding the source after correction.

- [ ] **Step 5: Persist scanner results page-by-page**

Update `ContentView` to append/update page records instead of calling `replacePages` with image-only data.

- [ ] **Step 6: Run tests and commit**

Commit:

```
feat: retain scanner source images for recropping
```

### Task 4: Replace the crop/editor interaction

**Files:**
- Modify: `KhanhScanner/Preview/ScannerPageEditorView.swift`
- Test: `KhanhScannerTests/ScannerV2GeometryTests.swift`

**Interfaces:**
- Page editor initializer receives an optional initial page ID.
- Crop editor edits `cropQuadrilateral` against `sourceImage`.
- Page editor exposes explicit finish semantics:
  - `onCancel`
  - `onDone`

- [ ] **Step 1: Write failing editor-state tests**

Verify tapping page N selects page N, crop edits update metadata rather than destructively replacing the source, rotate changes metadata, reorder preserves page identity, and delete chooses a valid next selection.

- [ ] **Step 2: Run CI and verify RED**

- [ ] **Step 3: Update editor state to metadata-based edits**

Do not mutate source pixels for crop/rotation. Rerender the selected page after metadata changes.

- [ ] **Step 4: Rebuild ManualPageCropView around the source image**

Initialize handles from the persisted crop quadrilateral. Add large invisible hit targets and a magnified crop corner preview while dragging. Apply only valid quadrilaterals.

- [ ] **Step 5: Remove the generic "Camera" label**

Use navigation Back/Cancel semantics controlled by the host context. Done always means commit.

- [ ] **Step 6: Run tests and commit**

Commit:

```
feat: recrop pages from original captures
```

### Task 5: Unify document preview and scanner navigation

**Files:**
- Modify: `KhanhScanner/Preview/ScanPreviewView.swift`
- Modify: `KhanhScanner/Session/DocumentSessionView.swift`
- Modify: `KhanhScanner/ScannerV2/ScannerV2ViewController.swift`
- Modify: `KhanhScanner/Scanner/DocumentScannerView.swift`
- Modify: `KhanhScanner/App/ContentView.swift`
- Test: `KhanhScannerTests/SmokeTests.swift`

**Interfaces:**
- `ScanPreviewView` takes:
  - document name
  - rendered pages
  - `onTapPage(Int)`
  - `onAddPages`
  - `onExport`
- Scanner page editor distinguishes cancel-to-camera from done-to-document.

- [ ] **Step 1: Add failing flow/state tests**

Cover:
- page tap opens the selected page;
- no standalone Edit button state exists;
- Add Pages is a primary action before Export PDF in the preview model;
- scanner editor Back resumes camera;
- scanner editor Done calls scanner completion instead of resuming the AR session.

- [ ] **Step 2: Run CI and verify RED**

- [ ] **Step 3: Simplify ScanPreviewView**

Remove the Edit button and top Add Pages text action. Make page cards tappable. Render full-width Add Pages above full-width Export PDF. Use the document name as the preview title.

- [ ] **Step 4: Consolidate document toolbar actions**

Replace separate Rename/Delete buttons with an ellipsis menu containing Rename and destructive Delete Document. Preserve delete confirmation and existing rename validation.

- [ ] **Step 5: Fix scanner editor navigation**

When opened from scanner thumbnail:
- Back dismisses editor and resumes AR session.
- Done commits drafts and calls the scanner delegate completion path.
- Do not restart the AR session after Done.

- [ ] **Step 6: Run tests and commit**

Commit:

```
fix: unify document preview and editor navigation
```

### Task 6: End-to-end verification and cleanup

**Files:**
- Modify only if verification finds defects.
- Test: all test targets.

**Interfaces:** None new.

- [ ] **Step 1: Run complete CI**

Run the existing iOS CI workflow against the branch head.

Expected: all tests pass.

- [ ] **Step 2: Verify backward compatibility tests**

Confirm old lifecycle catalogs, old PNG-only page documents, named documents, folders, bulk delete, and Scanner V2 geometry tests remain green.

- [ ] **Step 3: Audit the final UI code**

Verify there is no user-visible "Camera" button inside the generic editor, no standalone "Edit" control on document preview, and no destructive crop against rendered-only Scanner V2 sources.

- [ ] **Step 4: Update PR description**

Summarize raw-source persistence, true recrop, preview redesign, navigation semantics, migration behavior, and passing CI.

- [ ] **Step 5: Final commit if cleanup was needed**

Use a focused fix commit only if verification uncovered an issue.
