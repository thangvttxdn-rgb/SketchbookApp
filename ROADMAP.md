# Sketchbook Studio — Roadmap & Follow-ups

Tracking known issues and planned work. Items are ordered by priority. Tackle the
**P0 multi-page data-loss bug** first, ideally in the **1.3** update (after 1.2 is
approved on the App Store).

## P0 — Known bugs

### Multi-page: page content is lost when navigating between pages
- **Symptom:** Draw on page 1, add/flip to page 2, return to page 1 → page 1 is blank.
  The stroke that was visible is gone. This is **data loss**.
- **Scope:** Pre-existing since **v1.1** (verified: the live 1.1 build and the committed
  HEAD both reproduce it). It is *not* caused by the 1.2 drawing fixes, and the 1.2 fixes
  do not address it.
- **Where:** [Sketchbook/Drawing/CanvasView.swift](Sketchbook/Drawing/CanvasView.swift),
  [Sketchbook/Features/Editor/EditorView.swift](Sketchbook/Features/Editor/EditorView.swift)
  (`layerView` / `ForEach(... id: \.element.id)`),
  [Sketchbook/Features/Editor/EditorViewModel.swift](Sketchbook/Features/Editor/EditorViewModel.swift)
  (`goToPage` / `flushActiveDrawing` / `activeDrawing`).
- **Likely cause (to confirm):** the active layer's live `PKCanvasView` drawing is not
  reliably committed back into the page model before the page switches, and/or the
  per-page `CanvasView` (keyed by layer id) is torn down/recreated without restoring the
  page's stored `PKDrawing`. Investigate the commit-vs-page-switch ordering and whether the
  canvas reloads the new page's drawing on switch.
- **Definition of done:**
  - Drawing on any page persists across navigation, save/reload, and app relaunch.
  - `testMultiPage` asserts **page content** (e.g. the stroke is present/absent), not just
    the page indicator label — the current test passes while content is lost.

## P1 — Quality / UX

- **Brush-size label is nominal.** Since 1.2 the size slider value is mapped onto each
  ink's `validWidthRange`, so the `"NN pt"` label is no longer the literal point width.
  Either show the resolved width per brush or relabel the control (e.g. a 1–100% scale).
  See `BrushType.tool(color:width:)` in
  [Sketchbook/Models/BrushType.swift](Sketchbook/Models/BrushType.swift).
- **Undo memory.** Undo/redo stores full `SketchDocument` snapshots (capped at 30) in
  [EditorViewModel.swift](Sketchbook/Features/Editor/EditorViewModel.swift). For large
  multi-layer documents with raster data this can be heavy — consider per-layer or diff
  snapshots, or capping by total bytes.
- **System vs in-app undo.** The toolbar Undo now uses the document-level stack; the
  three-finger system-undo still drives PencilKit's own `undoManager`. Reconcile so both
  behave consistently.
- **Persist the default brush size** (currently a hard-coded `EditorViewModel.defaultBrushSize = 20`)
  as a Settings preference, alongside the existing default-brush / finger-drawing settings.

## P2 — Future features (ideas)

- ~~**Vector shapes**~~ — ✅ shipped: 1.3 (rect/circle/triangle/line) + 1.4 (diamond,
  star, pentagon, hexagon, arrow, heart).
- ~~**Fill vector shapes with color**~~ — ✅ shipped in 1.4: the fill tool hit-tests
  placed vector shapes (records kept per layer in `Layer.placedShapes`) and regenerates
  a crisp vector fill; taps elsewhere still raster flood-fill. Known limitation: the
  shape record survives even if the shape's strokes are later erased/lasso-deleted, so
  a tap there still "fills" the ghost shape.
- Stardust brush (1.4) is stamped via an overlay, so it doesn't work while zoomed
  (zoom is reset on select, like fill/shape modes) — consider mapping through
  PencilKit's zoomScale so overlay tools work zoomed-in.
- Adjustments (1.4) bake the active layer's strokes into a raster image on Apply
  (same as filters) — layer becomes non-editable ink afterwards.
- Stroke stabilization / smoothing options.
- Export to PDF (multi-page) and per-page PNG.
- Selection transform (move/scale/rotate) beyond PencilKit's lasso.
- Brush customization (opacity / texture) UI.

---
_Last updated alongside the 1.2 (build 11) submission._
