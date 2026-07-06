# Changelog

## [1.5]
- Major stability fix: all layers now zoom and pan together — strokes always land exactly where you draw them, on every layer, at every zoom level.
- One persistent drawing canvas across layer and page switches: switching layers no longer resets the zoom or drops in-flight strokes onto the wrong layer.
- Procreate-style quick gestures: two-finger tap to undo, three-finger tap to redo.
- New page-flip gesture: drag firmly past the bottom edge of the page for the next page (creates one past the last), past the top edge for the previous page (creates one before the first).
- Finger drawing is now off by default on iPad (Apple Pencil draws; fingers pan, zoom and undo) with a new one-tap toolbar toggle; on iPhone fingers still draw by default.
- Palm rejection while drawing: a resting palm can no longer pan or zoom the page mid-stroke.
- Layers panel: live thumbnail previews per layer (Procreate-style) and a per-layer opacity control.
- Pages sidebar: reliable thumbnails and smooth drag-to-reorder (stable page identity).
- Pickers and Adjustments open in the right side panel on iPad (auto-expanding) instead of a pop-up sheet over the canvas.
- Fixed layer opacity being applied twice to non-active layers.
- Fixed adjustments and filters erasing artwork in Dark Mode (ink was baked in colour-inverted, turning white on the white paper). Applies to all adjustments, filters, exports and thumbnails.
- Fixed a shape being dropped if you switched tools while still adjusting it — it is now baked in automatically (e.g. drag out a circle, then tap Fill: the circle stays and can be filled).
- Fill tool now opens a colour dialog right on the toolbar (colour well + quick swatches).
- Flood fill no longer treats ruled/grid template lines as boundaries.
- Autosave: your work is saved a few seconds after every change and when the app goes to the background.

## [1.4]
- Insert a Photo or Insert a File: add images from your photo library or the Files app as artwork layers (Procreate-style Add), alongside the existing tracing-reference import.
- The fill tool now fills vector shapes: tap inside a placed shape to give it a crisp vector fill in the current colour — tap again with a new colour to replace it.
- Canvas flood fill is fully undoable and re-fillable with another colour.
- New Adjustments panel with live preview: Hue/Saturation/Brightness, Colour Balance, Gradient Map, Gaussian Blur, Motion Blur, Noise, Sharpen, Bloom, Halftone and Chromatic Aberration.
- Six new shapes: Diamond, Star, Pentagon, Hexagon, Arrow and Heart.
- New Stardust brush that sprinkles twinkling stars and dust as you drag.
- Adjustable eraser size with a live size preview.
- Pages sidebar on iPad: see every page as a thumbnail, drag to reorder, tap the trash to delete, tap to jump to a page.
- Apple Pencil double-tap (or squeeze on Pencil Pro) toggles the eraser.
- Orientation lock now works on iPad; the editor opens locked to landscape and you can unlock or re-lock from the menu.
- Flick between pages with one finger in Pencil-only mode (two fingers any time); swiping up past the last page starts a new page.
- Grid/template and transform controls promoted to the top toolbar.
- Faster, cleaner colour fills, slimmer default shape outlines, and shape colour/fill updates apply live while placing a shape.

## [1.3]
- Vector shapes: draw rectangles, circles, triangles and straight lines.
- Shape handles: rotate to any angle, resize, and flip horizontally or vertically before placing.
- Optional solid fill colour for shapes, in addition to the outline.
- Flip a layer horizontally or vertically, and a new Fit to Canvas control.
- Lock the screen orientation explicitly to Portrait or Landscape (or Auto).
- New Motion Blur and Liquify effects.

## [1.2]
- Toolbar, brush library, multi-page and iPad side-panel improvements.
