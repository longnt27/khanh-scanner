# Document Editor Flow Redesign

Date: 2026-09-18
Branch: `fix/issue-20-editor-flow`
Related issue: #20

## Goal

Replace the current inconsistent preview/editor flow with one coherent document workflow:

1. The document screen is the canonical preview screen.
2. The document title is the persisted document name.
3. Add Pages is a primary action above Export PDF.
4. Tapping a page opens that page's editor directly.
5. Rename and Delete live under a single overflow menu.
6. Scanner thumbnail opens the same editor experience.
7. Crop operates on the original camera capture and editable document quadrilateral, not on an already-cropped page.

The design must preserve Scanner V2's document-detection quality and existing documents without destructive migration.

## Current Problems

The current implementation has several conflicting interaction models:

- `ScanPreviewView` shows both an Edit button and tappable pages, duplicating the same affordance.
- The preview title is hard-coded to "Preview" rather than the document name.
- Add Pages is visually secondary even though it is a primary document action.
- Rename and Delete occupy separate toolbar buttons.
- `ScannerPageEditorView` displays a "Camera" navigation button even when the destination is not meaningfully a camera flow.
- Saving edits from the scanner editor resumes the camera session, even when the user reasonably expects Done to finish editing and return to the document.
- Crop currently operates on the already perspective-corrected image, so it cannot recover pixels the automatic crop discarded.

The last point is the architectural problem. The current `ScannerPageDraft` stores only the rendered page image, so a true manual recrop is impossible.

## User Experience

### Document Preview

The document screen owns the high-level document actions.

Navigation title:

`session.name`

Top-right overflow menu:

- Rename
- Delete Document

Main content:

- horizontal or paged document preview
- tapping a page opens that page in the page editor

Primary actions, in this order:

1. Add Pages
2. Export PDF

Both are full-width actions. Add Pages appears directly above Export PDF.

There is no standalone Edit button. Editing is page-scoped and starts by tapping the page.

### Scanner

The camera keeps the existing Scanner V2 capture UI.

The bottom-left thumbnail represents the document's pages, including pages that existed before entering the scanner.

Tapping the thumbnail opens the page editor.

If the editor was opened from the scanner:

- Back returns to the scanner without committing editor changes.
- Done commits editor changes and finishes the scanner flow, returning to the document preview.
- Done does not resume the camera.

If the user wants to continue capturing after entering the editor, Back is the deliberate path back to camera.

The scanner's own Done button finishes capture and returns to the document preview.

### Page Editor

The page editor opens focused on the page the user tapped.

Available page actions:

- Crop
- Rotate left
- Rotate right
- Move earlier
- Move later
- Delete page

The editor may still show the thumbnail strip for navigating among pages, but there is no global Edit mode.

## Page Data Model

Introduce a persisted page record instead of treating a page as only a PNG.

Conceptually:

```
DocumentPage
- id
- sourceAsset
- cropQuadrilateral
- rotation
- renderedAsset
```

### Source asset

For Scanner V2 captures, the source asset is the full-resolution oriented camera image before perspective correction.

This source must be retained so the user can move crop corners outside the originally detected quadrilateral.

### Crop quadrilateral

Persist four normalized corners in source-image coordinates.

The automatic high-resolution Vision detection becomes the initial quadrilateral.

Manual crop edits update this quadrilateral.

### Rotation

Persist quarter-turn rotation metadata rather than repeatedly destructively rotating the source image.

### Rendered asset

The rendered page is derived from:

```
source image
  -> crop quadrilateral
  -> perspective correction
  -> rotation
  -> document enhancement
  -> final page image
```

The rendered image remains available for preview and PDF export so normal document browsing does not have to run image processing every frame.

## Persistence Layout

The session catalog continues to own document metadata and ordered page IDs.

Each page ID maps to page metadata and assets under the existing session page directory.

Recommended layout:

```
Pages/<session-id>/<page-id>/
    source.jpg
    rendered.png
    metadata.json
```

`metadata.json` contains:

- crop quadrilateral
- rotation
- format version

A repository API returns page records/rendered images in document order.

Mutations are page-aware:

- replace crop metadata and rerender one page
- rotate one page and rerender
- delete page
- reorder page IDs
- append newly captured page records

Do not rewrite every page in the document for a one-page edit.

## Backward Compatibility

Existing documents only contain rendered PNG pages.

They must load without migration failure.

For a legacy page:

- the existing rendered PNG becomes both the legacy source fallback and rendered page;
- crop quadrilateral defaults to the full image bounds;
- rotation defaults to zero.

This means legacy pages remain editable, but manual crop cannot reveal pixels that were discarded before this redesign. New Scanner V2 captures retain the true source image and therefore support full recrop.

Migration should be lazy. Do not eagerly rewrite every existing document at app launch.

## Capture Pipeline

Current Scanner V2 capture:

```
high-resolution frame
-> Vision document detection
-> perspective correction
-> page draft
```

New capture:

```
high-resolution frame
-> orient source image
-> Vision document detection
-> store source image
-> store detected quadrilateral
-> render page from source + quadrilateral
-> append page record
```

Sharpness gating should continue to evaluate the rectified document region rather than the whole frame.

Border cleanup and document enhancement stay in the render pipeline.

## Manual Crop

The crop screen displays the original source image, not the rendered page.

Initial handles are placed at the persisted crop quadrilateral.

The crop UI includes:

- four draggable corner handles;
- a visible quadrilateral outline;
- large touch targets around the handles;
- constrained normalized coordinates within the source image;
- corner magnification while dragging, so a fingertip does not obscure the exact edge.

Apply:

1. validate that the quadrilateral is non-self-intersecting and has usable area;
2. persist the new quadrilateral;
3. rerender the page through perspective correction, border cleanup, rotation, and enhancement;
4. update preview immediately.

Cancel leaves page metadata and rendered output unchanged.

## Navigation Semantics

Navigation behavior must be explicit rather than inferred from button labels.

### Editor launched from document preview

- Back/Cancel: discard uncommitted editor changes and return to document preview.
- Done: commit edits and return to document preview.

### Editor launched from scanner thumbnail

- Back: discard uncommitted editor changes and resume scanner.
- Done: commit edits, finish scanner, persist the resulting document, and return to document preview.

There is no "Camera" label in the generic page editor.

## Document Screen Toolbar

Replace the two independent Rename and Delete icons with an overflow menu.

Menu:

- Rename
- Delete Document (destructive)

Delete still requires destructive confirmation.

Rename still trims whitespace and rejects empty names.

## Error Handling

- If a source asset is missing but a rendered legacy page exists, fall back to the rendered page as source.
- If rerendering fails, keep the previous rendered asset and metadata unchanged.
- Page mutations must not leave catalog metadata pointing at missing assets.
- Scanner Done must not destroy existing pages if newly captured page processing fails.
- Crop validation failures should keep the crop screen open and explain the issue rather than silently applying an invalid shape.

## Testing

### Persistence tests

- new Scanner V2 page stores source, crop metadata, and rendered asset;
- existing legacy PNG-only page still loads;
- crop metadata persists across repository instances;
- rotation persists;
- reordering changes order without rewriting unrelated page content;
- deleting a page removes its assets;
- failed rerender leaves previous page intact.

### Image-processing tests

- manual crop is performed against the original source;
- changing quadrilateral changes the rendered perspective;
- full-bounds legacy crop preserves the image;
- rotation is applied after perspective correction;
- border cleanup still preserves clean page edges.

### Flow/state tests

- tapping page N opens editor at page N;
- document screen exposes Add Pages above Export PDF;
- scanner editor Back resumes scanner;
- scanner editor Done finishes scanner rather than resuming it;
- document editor Done returns to document preview;
- rename/delete are represented by the document action menu.

## Scope

This redesign covers the editor/preview/crop workflow and the page persistence changes required to support it.

It does not add OCR, annotations, drawing, signatures, filters beyond the existing enhancement pipeline, or cloud synchronization.
