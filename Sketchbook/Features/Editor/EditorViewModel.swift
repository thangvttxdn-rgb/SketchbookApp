import SwiftUI
import PencilKit

enum ToolMode: String, CaseIterable, Identifiable {
    case draw, erase, fill, lasso, shape
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .draw: return "paintbrush.pointed"
        case .erase: return "eraser"
        case .fill: return "drop.fill"
        case .lasso: return "lasso"
        case .shape: return "square.on.circle"
        }
    }
}

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var document: SketchDocument
    /// Default brush size (nominal slider value, 1...60).
    static let defaultBrushSize: CGFloat = 20

    @Published var brush: BrushType = .pen
    @Published var color: Color = .black { didSet { syncPendingShapeStyle() } }
    @Published var width: CGFloat = EditorViewModel.defaultBrushSize { didSet { syncPendingShapeStyle() } }
    @Published var eraseWidth: CGFloat = 24
    @Published var toolMode: ToolMode = .draw {
        didSet {
            // Leaving shape mode with a shape still being adjusted BAKES it in
            // instead of silently dropping it — e.g. drag out a circle, then
            // tap the fill tool: the circle must stay (and be fillable), not
            // disappear because its ✓ button was never tapped.
            if oldValue == .shape, toolMode != .shape, pendingShape != nil {
                commitPendingShape()
            }
        }
    }
    // MARK: Vector shapes
    @Published var shapeKind: ShapeKind = .rectangle
    /// Outline width for vector shapes — independent of the brush size so
    /// shape borders default to a slim outline.
    @Published var shapeStrokeWidth: CGFloat = 6 { didSet { syncPendingShapeStyle() } }
    @Published var shapeFillEnabled: Bool = false { didSet { syncPendingShapeStyle() } }
    @Published var shapeFillColor: Color = Color(hex: "#4C6EF5") { didSet { syncPendingShapeStyle() } }
    /// A shape being dragged out / adjusted via handles before it is baked in.
    @Published var pendingShape: PendingShape?

    /// Keep the live (pending) shape's style following the pickers, so toggling
    /// "Fill shape" or changing colours/width AFTER dragging the shape out
    /// updates it immediately instead of silently doing nothing.
    private func syncPendingShapeStyle() {
        guard pendingShape != nil else { return }
        pendingShape?.style = currentShapeStyle
    }
    @Published var isRulerActive = false
    @Published var symmetry: SymmetryMode = .off
    @Published var perspective: PerspectiveGuide = .off
    /// Palm rejection: when true, only Apple Pencil input draws (finger/palm ignored).
    /// Driven by the "Finger Drawing" setting (off → pencil-only → palm rejected).
    @Published var pencilOnly = true
    @Published var referenceOpacity: Double = 0.5
    @Published var lastSavedAt: Date?

    private var store: DocumentStore?

    // MARK: - Render caches (avoid re-rendering full-res images every view update,
    // which caused input latency when switching tools).
    private var templateCache: (TemplateKind, CGFloat, CGFloat, UIImage)?
    private var layerImageCache: [UUID: UIImage] = [:]

    // MARK: - Unified undo/redo (document snapshots)
    // A single timeline covering ALL content changes — strokes, fills, filter
    // effects, clears, and page/layer edits — not just PencilKit strokes.
    @Published private var undoStack: [SketchDocument] = []
    @Published private var redoStack: [SketchDocument] = []
    private let maxUndoSteps = 30

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Record the current document state so the next mutation can be undone.
    /// Call BEFORE applying a change. Also drops the thumbnail caches touched
    /// by the impending change and schedules a debounced autosave.
    private func snapshot() {
        undoStack.append(document)
        if undoStack.count > maxUndoSteps { undoStack.removeFirst() }
        redoStack.removeAll()
        if document.pages.indices.contains(document.currentPageIndex) {
            pageThumbCache.removeValue(forKey: document.pages[document.currentPageIndex].id)
        }
        if document.layers.indices.contains(activeIndex) {
            layerThumbCache.removeValue(forKey: document.layers[activeIndex].id)
        }
        scheduleAutosave()
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(document)
        document = prev
        invalidateLayerImage(nil)
        pageThumbCache.removeAll()
        layerThumbCache.removeAll()
        scheduleAutosave()
        Haptics.select()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
        invalidateLayerImage(nil)
        pageThumbCache.removeAll()
        layerThumbCache.removeAll()
        scheduleAutosave()
        Haptics.select()
    }

    // MARK: - Autosave (debounced)

    /// Persist a few seconds after the last change so force-quitting or a
    /// crash never loses more than a moment of work.
    private var autosaveTask: Task<Void, Never>?

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func templateImage(size: CGSize) -> UIImage {
        if let c = templateCache, c.0 == document.template, c.1 == size.width, c.2 == size.height {
            return c.3
        }
        let img = TemplateRenderer.render(document.template, size: size, backgroundColor: .clear)
        templateCache = (document.template, size.width, size.height, img)
        return img
    }

    func inactiveLayerImage(_ layer: Layer, size: CGSize) -> UIImage {
        if let img = layerImageCache[layer.id] { return img }
        let img = LayerCompositor.renderLayer(layer, size: size)
        layerImageCache[layer.id] = img
        return img
    }

    private func invalidateLayerImage(_ id: UUID?) {
        if let id { layerImageCache.removeValue(forKey: id) } else { layerImageCache.removeAll() }
    }

    init(document: SketchDocument) {
        self.document = document
        // Apply saved defaults (Settings).
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: SettingsKey.defaultBrush),
           let b = BrushType(rawValue: raw) {
            self.brush = b
        }
        // Finger drawing default: OFF on iPad (Pencil draws; fingers pan/zoom,
        // two-finger tap undoes — the notepad/GoodNotes model), ON on iPhone
        // (no Apple Pencil support, so fingers must draw). Toggle any time via
        // ••• → Finger Drawing or Settings.
        let fingerDefault = UIDevice.current.userInterfaceIdiom != .pad
        // bool(forKey:) (not `as? Bool`) so the "-fingerDrawing YES" launch
        // argument used by the UI tests coerces correctly.
        let fingerDrawing = defaults.object(forKey: SettingsKey.fingerDrawing) != nil
            ? defaults.bool(forKey: SettingsKey.fingerDrawing)
            : fingerDefault
        self.pencilOnly = !fingerDrawing
        if let e = defaults.object(forKey: SettingsKey.defaultEraseSize) as? Double, e > 0 {
            self.eraseWidth = CGFloat(e)
        }
        self.width = EditorViewModel.defaultBrushSize
        // If the default brush is the pencil, apply the saved grade.
        if brush == .pencil, let g = defaults.string(forKey: SettingsKey.defaultPencilGrade),
           let grade = PencilGrade(rawValue: g) {
            self.pencilGrade = grade
            self.width = grade.width
            self.color = grade.color
        }
    }

    /// Inject the environment store after init (StateObject can't read environment in init).
    func attach(store: DocumentStore) {
        if self.store == nil { self.store = store }
    }

    // MARK: - Active layer

    var activeIndex: Int { document.activeLayerIndex }

    var activeDrawing: PKDrawing {
        get {
            guard document.layers.indices.contains(activeIndex) else { return PKDrawing() }
            return document.layers[activeIndex].drawing
        }
        set {
            guard document.layers.indices.contains(activeIndex) else { return }
            // Each committed stroke is one undo step.
            guard document.layers[activeIndex].drawing != newValue else { return }
            snapshot()
            document.layers[activeIndex].drawing = newValue
        }
    }

    var activeLayerLocked: Bool {
        document.layers.indices.contains(activeIndex) ? document.layers[activeIndex].isLocked : true
    }

    // MARK: - Tool

    var currentTool: PKTool {
        switch toolMode {
        case .draw:
            return brush.tool(color: UIColor(color), width: width)
        case .erase:
            return PKEraserTool(.bitmap, width: eraseWidth)
        case .lasso:
            // PencilKit's lasso selects strokes and shows its own edit menu
            // (cut / copy / duplicate / move).
            return PKLassoTool()
        case .fill, .shape:
            // Fill and shape use overlay gestures, not a PencilKit tool; the
            // canvas is locked in these modes, so keep a harmless pen.
            return brush.tool(color: UIColor(color), width: width)
        }
    }

    // MARK: - Vector shapes

    /// Style captured from the current stroke colour / shape outline width +
    /// shape fill choice.
    var currentShapeStyle: ShapeStyle {
        ShapeStyle(strokeColor: color, strokeWidth: shapeStrokeWidth,
                   fillColor: (shapeFillEnabled && shapeKind.canFill) ? shapeFillColor : nil)
    }

    func selectShape(_ kind: ShapeKind) {
        shapeKind = kind
        toolMode = .shape
        pendingShape = nil
        Haptics.select()
    }

    /// Begin adjusting a shape dragged out to `rect` (canvas coordinates).
    func beginShape(rect: CGRect) {
        guard !activeLayerLocked else { return }
        pendingShape = PendingShape(kind: shapeKind, rect: rect, style: currentShapeStyle)
    }

    func cancelPendingShape() { pendingShape = nil }

    /// Bake the pending shape into the active layer as PKStrokes (fill + outline),
    /// going through `activeDrawing` so it is one undo step and behaves like ink.
    /// A `PlacedShape` record is kept alongside so the fill tool can later
    /// tap-to-fill the shape.
    func commitPendingShape() {
        guard let shape = pendingShape else { return }
        pendingShape = nil
        guard !activeLayerLocked else { return }
        let strokes = ShapeFactory.strokes(for: shape)
        guard !strokes.isEmpty else { return }
        var drawing = activeDrawing
        drawing.strokes.append(contentsOf: strokes)
        activeDrawing = drawing   // snapshots + commits
        let placed = PlacedShape(kind: shape.kind,
                                 rect: shape.normalizedRect,
                                 rotation: shape.rotation,
                                 flipH: shape.flipH,
                                 flipV: shape.flipV,
                                 strokeColorHex: UIColor(shape.style.strokeColor).hexString,
                                 strokeWidth: shape.style.strokeWidth)
        document.layers[activeIndex].placedShapes = (document.layers[activeIndex].placedShapes ?? []) + [placed]
        Haptics.select()
    }

    // MARK: - Flip (active layer)

    func flipHorizontal() { flip(horizontal: true) }
    func flipVertical() { flip(horizontal: false) }

    private func flip(horizontal: Bool) {
        guard document.layers.indices.contains(activeIndex), !activeLayerLocked else { return }
        snapshot()
        let size = document.canvasSize
        let t = horizontal
            ? CGAffineTransform(translationX: size.width, y: 0).scaledBy(x: -1, y: 1)
            : CGAffineTransform(translationX: 0, y: size.height).scaledBy(x: 1, y: -1)

        var drawing = document.layers[activeIndex].drawing
        drawing.transform(using: t)
        document.layers[activeIndex].drawing = drawing

        if let img = document.layers[activeIndex].image {
            let flipped = UIGraphicsImageRenderer(size: size).image { ctx in
                ctx.cgContext.concatenate(t)
                img.draw(in: CGRect(origin: .zero, size: size))
            }
            document.layers[activeIndex].imageData = flipped.pngData()
        }
        // Keep the vector-shape records in sync so tap-to-fill still hits them.
        if var shapes = document.layers[activeIndex].placedShapes {
            for i in shapes.indices {
                if horizontal {
                    shapes[i].rect.origin.x = size.width - shapes[i].rect.maxX
                    shapes[i].flipH.toggle()
                } else {
                    shapes[i].rect.origin.y = size.height - shapes[i].rect.maxY
                    shapes[i].flipV.toggle()
                }
                shapes[i].rotation = -shapes[i].rotation
            }
            document.layers[activeIndex].placedShapes = shapes
        }
        invalidateLayerImage(document.layers[activeIndex].id)
        Haptics.select()
    }

    /// Currently selected graphite grade (when the pencil brush is in use).
    @Published var pencilGrade: PencilGrade?

    func selectBrush(_ b: BrushType) {
        brush = b
        // Keep the current size so it acts as a persistent global default
        // (starts at `defaultBrushSize`); switching brushes no longer resets it.
        pencilGrade = nil
        toolMode = .draw
        Haptics.select()
    }

    /// Select a graphite pencil grade — sets the pencil ink with grade darkness + width.
    func selectPencilGrade(_ grade: PencilGrade) {
        brush = .pencil
        width = grade.width
        color = grade.color
        pencilGrade = grade
        toolMode = .draw
        Haptics.select()
    }

    /// Apple Pencil double-tap / squeeze: toggle between the eraser and the
    /// drawing tool (returning to draw mode from any non-erase tool).
    func togglePencilEraser() {
        toolMode = (toolMode == .erase) ? .draw : .erase
        Haptics.select()
    }

    // MARK: - Finger drawing

    /// Whether finger (touch) input draws. When off, only Apple Pencil draws and
    /// fingers pan/zoom (palm rejection). Mirrors the Settings default.
    var fingerDrawingEnabled: Bool { !pencilOnly }

    func setFingerDrawing(_ on: Bool) {
        pencilOnly = !on
        UserDefaults.standard.set(on, forKey: SettingsKey.fingerDrawing)
        Haptics.select()
    }

    // MARK: - Pages

    var pageCount: Int { document.pages.count }
    var currentPage: Int { document.currentPageIndex }

    /// Add a new blank page after the current one and switch to it.
    func addPage() { addPageAfter() }

    /// Insert a blank page immediately before the current page and switch to it.
    func addPageBefore() {
        snapshot()
        flushActiveDrawing()
        let insertAt = document.currentPageIndex
        document.pages.insert(Page(), at: insertAt)
        document.currentPageIndex = insertAt
        Haptics.select()
    }

    /// Insert a blank page immediately after the current page and switch to it.
    func addPageAfter() {
        snapshot()
        flushActiveDrawing()
        let insertAt = document.currentPageIndex + 1
        document.pages.insert(Page(), at: insertAt)
        document.currentPageIndex = insertAt
        Haptics.select()
    }

    func goToPage(_ index: Int) {
        guard document.pages.indices.contains(index), index != document.currentPageIndex else { return }
        flushActiveDrawing()
        document.currentPageIndex = index
        Haptics.select()
    }

    /// Next page, or create one when swiping past the last page.
    func nextPageOrCreate() {
        if document.currentPageIndex < document.pages.count - 1 {
            goToPage(document.currentPageIndex + 1)
        } else {
            addPage()
        }
    }

    func previousPage() {
        guard document.currentPageIndex > 0 else { return }
        goToPage(document.currentPageIndex - 1)
    }

    /// Previous page, or — when already on the first page — create a new page
    /// before it (notepad-style: a firm pull past the top edge always lands on
    /// a page, prepending a blank one at the start when there is none).
    func previousPageOrCreate() {
        if document.currentPageIndex > 0 {
            goToPage(document.currentPageIndex - 1)
        } else {
            addPageBefore()
        }
    }

    func deleteCurrentPage() {
        guard document.pages.count > 1 else { clearCurrentPage(); return }
        snapshot()
        document.pages.remove(at: document.currentPageIndex)
        document.currentPageIndex = min(document.currentPageIndex, document.pages.count - 1)
        invalidateLayerImage(nil)
        Haptics.select()
    }

    /// Remove every page and start over with a single blank page.
    func deleteAllPages() {
        snapshot()
        document.pages = [Page()]
        document.currentPageIndex = 0
        invalidateLayerImage(nil)
        Haptics.select()
    }

    /// Wipe the current page's content back to one blank layer (keeps the page).
    func clearCurrentPage() {
        snapshot()
        document.pages[document.currentPageIndex] = Page()
        invalidateLayerImage(nil)
        Haptics.select()
    }

    /// Wipe every page's content but keep the page count.
    func clearAllPages() {
        snapshot()
        for i in document.pages.indices { document.pages[i] = Page() }
        invalidateLayerImage(nil)
        Haptics.select()
    }

    // MARK: - Pages sidebar (thumbnails, reorder, delete)

    private var pageThumbCache: [UUID: UIImage] = [:]
    private var layerThumbCache: [UUID: UIImage] = [:]

    /// Thumbnail for the pages sidebar. Cached per page (current page included —
    /// its entry is dropped on every undoable change, see `snapshot`), so the
    /// sidebar never re-renders a full page composite per view update.
    func pageThumbnail(_ index: Int) -> UIImage {
        guard document.pages.indices.contains(index) else { return UIImage() }
        let page = document.pages[index]
        if let cached = pageThumbCache[page.id] { return cached }
        let img = LayerCompositor.renderPage(page, canvasSize: document.canvasSize,
                                             backgroundHex: document.backgroundHex)
        pageThumbCache[page.id] = img
        return img
    }

    /// Small preview of one layer for the layers panel (Procreate-style).
    /// Cached per layer; the active layer's entry is dropped on each change.
    func layerThumbnail(_ index: Int) -> UIImage {
        guard document.layers.indices.contains(index) else { return UIImage() }
        let layer = document.layers[index]
        if let cached = layerThumbCache[layer.id] { return cached }
        let img = LayerCompositor.renderLayerThumb(layer, canvasSize: document.canvasSize,
                                                   backgroundHex: document.backgroundHex)
        layerThumbCache[layer.id] = img
        return img
    }

    /// True while a drag-reorder is in flight (one undo snapshot per drag).
    private var pageReorderSnapshotted = false

    func endPageReorder() { pageReorderSnapshotted = false }

    /// Reorder pages during a drag. Snapshots lazily on the FIRST move of a
    /// drag — snapshotting at drag-lift re-renders the sidebar and cancels the
    /// drag session.
    func movePage(fromIndex: Int, toIndex: Int) {
        guard document.pages.indices.contains(fromIndex),
              toIndex >= 0, toIndex < document.pages.count, fromIndex != toIndex else { return }
        if !pageReorderSnapshotted {
            snapshot()
            pageReorderSnapshotted = true
        }
        let currentId = document.pages[document.currentPageIndex].id
        let page = document.pages.remove(at: fromIndex)
        document.pages.insert(page, at: toIndex)
        if let idx = document.pages.firstIndex(where: { $0.id == currentId }) {
            document.currentPageIndex = idx
        }
        invalidateLayerImage(nil)
    }

    /// Delete a specific page (undoable). The last remaining page is cleared
    /// instead of removed.
    func deletePage(at index: Int) {
        guard document.pages.indices.contains(index) else { return }
        guard document.pages.count > 1 else { clearCurrentPage(); return }
        snapshot()
        pageThumbCache.removeValue(forKey: document.pages[index].id)
        document.pages.remove(at: index)
        if document.currentPageIndex >= document.pages.count {
            document.currentPageIndex = document.pages.count - 1
        } else if index < document.currentPageIndex {
            document.currentPageIndex -= 1
        }
        invalidateLayerImage(nil)
        Haptics.select()
    }

    /// Next page without auto-creating (used by the swipe gesture).
    func nextPage() {
        guard document.currentPageIndex < document.pages.count - 1 else { return }
        goToPage(document.currentPageIndex + 1)
    }

    /// Ensure the latest PencilKit strokes are committed to the model before a
    /// page switch (the canvas pushes changes asynchronously).
    private func flushActiveDrawing() {
        guard document.layers.indices.contains(activeIndex) else { return }
        invalidateLayerImage(document.layers[activeIndex].id)
    }

    // MARK: - Layers

    func addLayer() {
        snapshot()
        let layer = Layer(name: "Layer \(document.layers.count + 1)")
        document.layers.append(layer)
        document.activeLayerIndex = document.layers.count - 1
    }

    func duplicateActiveLayer() {
        guard document.layers.indices.contains(activeIndex) else { return }
        snapshot()
        var copy = document.layers[activeIndex]
        copy.id = UUID()
        copy.name += " copy"
        document.layers.insert(copy, at: activeIndex + 1)
        document.activeLayerIndex = activeIndex + 1
    }

    func deleteLayer(at index: Int) {
        guard document.layers.count > 1, document.layers.indices.contains(index) else { return }
        snapshot()
        document.layers.remove(at: index)
        document.activeLayerIndex = min(document.activeLayerIndex, document.layers.count - 1)
    }

    func moveLayer(from source: IndexSet, to destination: Int) {
        snapshot()
        document.layers.move(fromOffsets: source, toOffset: destination)
        invalidateLayerImage(nil)
    }

    func setActiveLayer(_ index: Int) {
        guard document.layers.indices.contains(index) else { return }
        // The layer we're leaving may have changed — drop its cached image so it
        // re-renders correctly as an inactive layer.
        if document.layers.indices.contains(activeIndex) {
            invalidateLayerImage(document.layers[activeIndex].id)
        }
        document.activeLayerIndex = index
        invalidateLayerImage(document.layers[index].id)
    }

    func renameLayer(at index: Int, to name: String) {
        guard document.layers.indices.contains(index) else { return }
        document.layers[index].name = name
    }

    /// Distinct group names currently in use.
    var groupNames: [String] {
        var seen = [String]()
        for l in document.layers { if let g = l.groupName, !seen.contains(g) { seen.append(g) } }
        return seen
    }

    func setGroup(at index: Int, to name: String?) {
        guard document.layers.indices.contains(index) else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        document.layers[index].groupName = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// Toggle visibility for every layer in a group at once.
    func toggleGroupVisibility(_ group: String) {
        let anyVisible = document.layers.contains { $0.groupName == group && $0.isVisible }
        for i in document.layers.indices where document.layers[i].groupName == group {
            document.layers[i].isVisible = !anyVisible
        }
    }

    // MARK: - Color fill

    /// Fill from a tap, in canvas pixel coordinates. If the tap lands inside a
    /// vector shape on the active layer, the shape takes a crisp vector fill in
    /// the current colour (tap again with a new colour to replace it); anywhere
    /// else falls back to the raster flood fill. Both are single undo steps.
    func performFill(at point: CGPoint) {
        guard document.layers.indices.contains(activeIndex),
              !document.layers[activeIndex].isLocked else { return }
        if let placed = (document.layers[activeIndex].placedShapes ?? [])
            .last(where: { ShapeFactory.hitTest($0, point: point) }) {
            let strokes = ShapeFactory.refillStrokes(for: placed, fillColor: UIColor(color))
            guard !strokes.isEmpty else { return }
            var drawing = activeDrawing
            drawing.strokes.append(contentsOf: strokes)
            activeDrawing = drawing   // snapshots + commits (one undo step)
            Haptics.select()
            return
        }
        // Boundaries come from the ARTWORK only (no background/template):
        // otherwise ruled/grid template lines fence the flood fill into thin
        // bands and fills look broken on any non-blank paper.
        let base = LayerCompositor.composite(document, includeReference: false,
                                             includeBackground: false, scale: 1)
        guard let patch = FloodFill.fill(in: base, at: point, with: UIColor(color)) else { return }
        snapshot()
        // Composite the filled patch onto the active layer's raster image.
        let size = document.canvasSize
        let merged = UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size)
            document.layers[activeIndex].image?.draw(in: rect)
            patch.draw(in: rect)
        }
        document.layers[activeIndex].imageData = merged.pngData()
        invalidateLayerImage(document.layers[activeIndex].id)
    }

    // MARK: - Insert image content (Procreate-style "Add")

    /// Insert an image (from Photos or Files) as a NEW content layer, scaled to
    /// fit within the canvas and centred. Unlike a tracing reference it is part
    /// of the artwork and included in exports. One undo step.
    func insertImage(_ image: UIImage) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        snapshot()
        let size = document.canvasSize
        let ratio = min(size.width * 0.85 / image.size.width,
                        size.height * 0.85 / image.size.height, 1)
        let target = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let origin = CGPoint(x: (size.width - target.width) / 2,
                             y: (size.height - target.height) / 2)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let composed = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: target))
        }
        let layer = Layer(name: "Image \((document.layers.filter { $0.image != nil }.count) + 1)",
                          imageData: composed.pngData())
        document.layers.append(layer)
        document.activeLayerIndex = document.layers.count - 1
        Haptics.select()
    }

    // MARK: - Stardust brush

    /// Particles sprinkled during the current drag, previewed by the overlay.
    @Published var stardustStamps: [StardustStamp] = []
    private var lastSprinklePoint: CGPoint?

    var isStardustActive: Bool { toolMode == .draw && brush == .stardust }

    /// Scatter stardust along the drag. `point` is in canvas coordinates;
    /// `displayScale` converts the nominal brush size to canvas pixels so the
    /// sprinkle matches the on-screen brush size.
    func sprinkleStardust(at point: CGPoint, displayScale: CGFloat) {
        guard !activeLayerLocked, stardustStamps.count < Stardust.maxStampsPerStroke else { return }
        let brushSize = width / max(displayScale, 0.0001) * 0.9
        let new = Stardust.scatter(from: lastSprinklePoint, to: point, brushSize: brushSize)
        guard !new.isEmpty || lastSprinklePoint == nil else { return }
        lastSprinklePoint = point
        stardustStamps.append(contentsOf: new)
    }

    /// Bake the sprinkled stamps into the active layer as one undo step.
    func endStardustStroke() {
        defer { stardustStamps = []; lastSprinklePoint = nil }
        guard !activeLayerLocked, !stardustStamps.isEmpty else { return }
        let strokes = Stardust.strokes(for: stardustStamps, color: UIColor(color))
        guard !strokes.isEmpty else { return }
        var drawing = activeDrawing
        drawing.strokes.append(contentsOf: strokes)
        activeDrawing = drawing   // snapshots + commits
        Haptics.select()
    }

    // MARK: - Adjustments (apply to active layer, undoable)

    func applyAdjustment(_ adjustment: SketchAdjustment, params: [String: Double]) {
        guard document.layers.indices.contains(activeIndex),
              !document.layers[activeIndex].isLocked else { return }
        snapshot()
        let size = document.canvasSize
        let rendered = LayerCompositor.renderLayer(document.layers[activeIndex], size: size, scale: 1)
        let adjusted = AdjustmentEngine.apply(adjustment, to: rendered, params: params)
        document.layers[activeIndex].imageData = adjusted.pngData()
        document.layers[activeIndex].drawing = PKDrawing() // baked into the image
        invalidateLayerImage(document.layers[activeIndex].id)
        Haptics.select()
    }

    /// Small composite of the active layer used for the adjustments live preview.
    func adjustmentPreviewBase(maxDimension: CGFloat = 480) -> UIImage {
        let size = document.canvasSize
        let ratio = min(maxDimension / size.width, maxDimension / size.height, 1)
        let target = CGSize(width: max(size.width * ratio, 1), height: max(size.height * ratio, 1))
        guard document.layers.indices.contains(activeIndex) else {
            return UIGraphicsImageRenderer(size: target).image { _ in }
        }
        let layer = document.layers[activeIndex]
        let full = LayerCompositor.renderLayer(layer, size: size, scale: 1)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            full.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    // MARK: - Reference image (upload + overlay for tracing)

    func importReference(_ image: UIImage) {
        snapshot()
        let layer = Layer(name: "Reference",
                          opacity: referenceOpacity,
                          imageData: image.pngData(),
                          isReference: true)
        document.layers.append(layer)
        // Keep the active (drawing) layer selected so the user traces over it.
    }

    var referenceLayerIndex: Int? { document.layers.firstIndex { $0.isReference } }

    func updateReferenceOpacity(_ value: Double) {
        referenceOpacity = value
        if let i = referenceLayerIndex { document.layers[i].opacity = value }
    }

    // MARK: - Filters (apply to active layer)

    func applyFilter(_ filter: SketchFilter) {
        guard filter != .none, document.layers.indices.contains(activeIndex) else { return }
        snapshot()
        let size = document.canvasSize
        let rendered = LayerCompositor.renderLayer(document.layers[activeIndex], size: size, scale: 1)
        let filtered = FilterEngine.apply(filter, to: rendered)
        document.layers[activeIndex].imageData = filtered.pngData()
        document.layers[activeIndex].drawing = PKDrawing() // baked into the image
        invalidateLayerImage(document.layers[activeIndex].id)
    }

    // MARK: - Templates / background

    func setTemplate(_ template: TemplateKind) {
        snapshot()
        document.template = template
        templateCache = nil
    }

    // MARK: - Persistence

    func save() {
        document.thumbnailData = LayerCompositor.thumbnail(document).pngData()
        guard let store else { return }
        let saved = store.save(document)
        document = saved
        lastSavedAt = saved.modifiedAt
    }

    /// Flattened export used by AR / share (excludes tracing references).
    func exportedImage() -> UIImage {
        LayerCompositor.composite(document, includeReference: false, includeBackground: true, scale: 2)
    }
}
