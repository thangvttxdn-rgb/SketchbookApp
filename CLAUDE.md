# CLAUDE.md

Guidance for working in this repository.

## Project

**Sketchbook Studio** — a native iPhone & iPad sketching app (SwiftUI + PencilKit +
RealityKit). Live on the App Store (bundle `com.tertiaryinfotech.sketchbookapp`, team
`GU9WTSTX9M`).

## Structure

- `Sketchbook/App/` — app entry, orientation lock.
- `Sketchbook/Drawing/` — `CanvasView` (the `PKCanvasView` wrapper), symmetry, perspective
  guides, templates, flood fill, filters, layer compositor.
- `Sketchbook/Models/` — `SketchDocument` (multi-page, Codable + legacy migration), `Page`,
  `Layer`, `BrushType` (brush library → PencilKit ink types), `PencilGrade`, `Template`.
- `Sketchbook/Features/` — `Editor` (view + `EditorViewModel` + toolbar/side panels),
  `Gallery`, `Settings`, `About`.
- `Sketchbook/Store/` — `DocumentStore` (iCloud + local), sample art.
- `SketchbookUITests/` — XCUITest screenshots + drawing/multi-page validation.

## Build & release

- **XcodeGen project**: edit `project.yml`, then `xcodegen generate` (a PostToolUse hook in
  `.claude/settings.json` runs it automatically after any `project.yml` edit). The version is
  `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml`; `App/Info.plist` uses
  `$(…)` placeholders, so bump only `project.yml`.
- **Build number must strictly increase** on every App Store upload.
- App Store submission is driven via the App Store Connect API — see the
  `app-store-submission` / `ios-app-update` skills and the gitignored `.env`
  (`ASC_*` keys; the `.p8` lives outside the repo). Never commit `.env` or `*.p8`.
- Install on a device: `ios-install-device` skill (`xcrun devicectl`).

## Conventions

- Keep drawing input robust: a SwiftUI `.scaleEffect` over `PKCanvasView` breaks Pencil/
  touch input — use PencilKit's own `zoomScale` for canvas zoom. Never reassign
  `canvas.drawing` while a stroke is in progress (gate on `canvasViewDidBegin/EndUsingTool`),
  or the live stroke is cancelled.
- Commit drawing changes to the model synchronously on stroke end (not async), to avoid a
  re-render resetting the canvas to a stale value.
- **One persistent `PKCanvasView`** (1.5+): the editor renders exactly one canvas, outside
  the layer `ForEach`, with image layers split below/above it. Never move it back inside the
  ForEach — recreating the canvas per layer switch resets zoom and can commit an in-flight
  stroke to the wrong layer (the shared `activeDrawing` binding resolves at call time).
- **Viewport sync** (1.5+): the canvas is the only zoomable scroll view; it reports
  `zoomScale`/`contentOffset` up (`onViewportChange`) and every sibling layer/template/guide
  image applies `scaleEffect(zoom/fit, anchor: .topLeading).offset(-contentOffset)` so all
  layers stay in register. Don't reassign `contentSize` while zoomed (it clips the viewport).
- Page-flip gesture is an overscroll pull (drag ~110 pt past the top/bottom edge at fit
  zoom), not a swipe recognizer. Two-finger tap = undo, three-finger tap = redo.
- Finger drawing defaults OFF on iPad (Pencil-only; fingers pan/zoom) and ON on iPhone —
  keep `EditorViewModel.init` and `SettingsView` in agreement; UI tests pass
  `-fingerDrawing YES` so synthetic touches draw.
- **Render PKDrawing under light traits only** (1.5+): in Dark Mode `PKDrawing.image`
  returns colour-INVERTED ink (black → white), which silently wipes artwork when baked
  (adjustments, filters, exports, thumbnails). All rasterisation goes through
  `LayerCompositor` (`renderInLightMode`) — never call `drawing.image(from:scale:)` outside
  it without pinning `UITraitCollection(userInterfaceStyle: .light)`.
- A pending vector shape is COMMITTED (not dropped) when the tool mode leaves `.shape` or
  on Back — see `EditorViewModel.toolMode.didSet`. Tool buttons that open pickers use the
  tap-again pattern (first tap selects the tool, second opens its popover); a popover on
  the first tap swallows the next canvas tap as its dismissal.
- Flood-fill boundary detection composites the ARTWORK only (`includeBackground: false`) —
  template grid/ruled lines must not fence fills.

## Follow-ups / future work

See **[ROADMAP.md](ROADMAP.md)** for the tracked backlog. **1.5** (in review) fixed the
layer/zoom registration, dark-mode adjustment wipe, pull-to-flip/create pages, and shipped
vector-shape colour fills, layer thumbnails and the fill colour dialog. Update ROADMAP.md
as items are completed or added.
