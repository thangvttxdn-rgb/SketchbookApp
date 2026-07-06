import SwiftUI
import PencilKit

/// Holds a weak reference to the live PKCanvasView so the toolbar can drive
/// PencilKit's undo/redo.
final class CanvasHandle: ObservableObject {
    weak var canvas: PKCanvasView?
    func undo() { canvas?.undoManager?.undo() }
    func redo() { canvas?.undoManager?.redo() }
    var canUndo: Bool { canvas?.undoManager?.canUndo ?? false }
    var canRedo: Bool { canvas?.undoManager?.canRedo ?? false }
    /// Reset pinch-zoom back to the fit-to-screen scale.
    func resetZoom() {
        guard let canvas else { return }
        canvas.setZoomScale(canvas.minimumZoomScale, animated: true)
    }
}

/// SwiftUI wrapper around `PKCanvasView` for the active layer.
///
/// - Apple Pencil + palm rejection are handled by PencilKit; `pencilOnly`
///   switches the drawing policy so a resting palm (or any finger) is ignored.
/// - Live symmetry mirroring is applied on stroke commit via the coordinator.
/// - The canvas is the ONE zoomable scroll view; its live zoom/offset is
///   reported up via `onViewportChange` so the surrounding SwiftUI layer
///   images can be transformed to match (otherwise only the active layer's
///   ink zooms and strokes appear "in the wrong place" next to other layers).
struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var tool: PKTool
    var isRulerActive: Bool
    var pencilOnly: Bool
    var symmetry: SymmetryMode
    var canvasSize: CGSize
    var isLocked: Bool
    var handle: CanvasHandle?
    /// GoodNotes-style page pull: dragging firmly past the bottom edge (and
    /// releasing) flips to the next page / creates one; past the top edge goes
    /// to the previous page. Only fires at the fit (unzoomed) scale.
    var onPullNext: (() -> Void)?
    var onPullPrevious: (() -> Void)?
    /// Procreate-style quick gestures: two-finger tap = undo, three-finger
    /// tap = redo.
    var onTwoFingerTap: (() -> Void)?
    var onThreeFingerTap: (() -> Void)?
    /// Apple Pencil double-tap (2nd gen) / squeeze (Pencil Pro) — used to
    /// toggle between the current tool and the eraser.
    var onPencilAction: (() -> Void)?
    /// Reports the live zoom scale + content offset so sibling layers render
    /// in register with the canvas content.
    var onViewportChange: ((CGFloat, CGPoint) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        handle?.canvas = canvas

        let pencil = UIPencilInteraction()
        pencil.delegate = context.coordinator
        canvas.addInteraction(pencil)

        // Two-finger tap → undo, three-finger tap → redo (fingers only; the
        // Pencil never triggers these).
        for (touches, action) in [(2, #selector(Coordinator.handleTwoFingerTap(_:))),
                                  (3, #selector(Coordinator.handleThreeFingerTap(_:)))] {
            let tap = UITapGestureRecognizer(target: context.coordinator, action: action)
            tap.numberOfTouchesRequired = touches
            tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            tap.delegate = context.coordinator
            canvas.addGestureRecognizer(tap)
        }

        canvas.drawing = drawing
        context.coordinator.lastPushedUp = drawing
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // Vertical bounce enables the pull-past-the-edge page gesture.
        canvas.alwaysBounceVertical = true
        canvas.alwaysBounceHorizontal = false
        canvas.bouncesZoom = false
        canvas.showsVerticalScrollIndicator = false
        canvas.showsHorizontalScrollIndicator = false
        // No automatic safe-area insets: the sibling layer images are aligned
        // to the reported contentOffset, which must stay in pure content space.
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.contentSize = canvasSize
        context.coordinator.lastContentSize = canvasSize
        applyConfig(canvas)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        // Only push the binding INTO the canvas when the change came from outside
        // (page/layer switch, clear, filter, undo) — never when it's the value the
        // canvas itself just reported up, and NEVER while a stroke is in progress
        // (that cancels the live stroke — the "can't draw with the panel open" bug).
        let coord = context.coordinator
        if !coord.isDrawing,
           canvas.drawing != drawing,
           drawing != coord.lastPushedUp,
           !coord.isApplyingSymmetry {
            coord.isPullingIn = true
            canvas.drawing = drawing
            coord.isPullingIn = false
            coord.syncStrokeCount(drawing.strokes.count)
            coord.lastPushedUp = drawing
        }
        applyConfig(canvas)
        // Fit the fixed-size drawing canvas into the on-screen frame using
        // PencilKit's own zoom (NOT a SwiftUI .scaleEffect, which breaks Pencil
        // touch handling). Drawing stays in canvasSize coordinates.
        //
        // contentSize is only (re)assigned when the underlying canvas size
        // actually changes: UIScrollView scales contentSize with the zoom, so
        // blindly resetting it every update while the user is zoomed in
        // clips/jumps the viewport (the "zoom keeps snapping" bug).
        if coord.lastContentSize != canvasSize {
            canvas.contentSize = canvasSize
            coord.lastContentSize = canvasSize
            coord.didInitialZoom = false
        }
        let bounds = canvas.bounds.size
        if bounds.width > 0, bounds.height > 0 {
            let fit = min(bounds.width / canvasSize.width, bounds.height / canvasSize.height)
            if fit > 0, fit.isFinite {
                // Pinch-to-zoom is handled by PencilKit's own scroll-view zoom
                // (1×–5× of the fit scale). `fit` is the zoomed-out baseline.
                canvas.minimumZoomScale = fit
                canvas.maximumZoomScale = fit * 5
                // Snap to fit only on first layout / when the user is zoomed out
                // past the new baseline; never fight an active user zoom.
                if !coord.didInitialZoom || canvas.zoomScale < fit {
                    canvas.zoomScale = fit
                    coord.didInitialZoom = true
                    coord.reportViewport(canvas)
                }
            }
        }
    }

    private func applyConfig(_ canvas: PKCanvasView) {
        canvas.tool = tool
        canvas.isRulerActive = isRulerActive
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        canvas.isUserInteractionEnabled = !isLocked
        // In Dark Mode PencilKit inverts ink colors (black ink → white), making
        // black strokes invisible on the white canvas. Pin the canvas to light
        // so ink renders in the authored color.
        canvas.overrideUserInterfaceStyle = .light
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate,
                             UIPencilInteractionDelegate {
        var parent: CanvasView
        var isApplyingSymmetry = false
        var didInitialZoom = false
        /// Last canvasSize pushed to `contentSize` (see updateUIView).
        var lastContentSize: CGSize = .zero
        /// True between tool-down and tool-up. While true, `updateUIView` must not
        /// reassign `canvas.drawing`, or the active stroke is cancelled.
        var isDrawing = false
        /// True while we are programmatically assigning `canvas.drawing` from the
        /// binding, so the resulting delegate callback doesn't echo it back.
        var isPullingIn = false
        /// The last drawing this canvas reported up through the binding. Used to
        /// distinguish our own round-trip from a genuine external change so
        /// `updateUIView` doesn't overwrite a stroke in progress.
        var lastPushedUp: PKDrawing?
        private var lastStrokeCount = 0
        /// Re-enables scrolling shortly after the tool lifts so a resting palm
        /// can't pan the canvas in the gaps between strokes.
        private var scrollReEnableWork: DispatchWorkItem?
        /// One page flip per drag gesture.
        private var pullFired = false

        init(_ parent: CanvasView) {
            self.parent = parent
            self.lastStrokeCount = parent.drawing.strokes.count
        }

        func syncStrokeCount(_ count: Int) { lastStrokeCount = count }

        // MARK: Quick gestures

        @objc func handleTwoFingerTap(_ gr: UITapGestureRecognizer) {
            guard gr.state == .ended, !isDrawing else { return }
            parent.onTwoFingerTap?()
        }

        @objc func handleThreeFingerTap(_ gr: UITapGestureRecognizer) {
            guard gr.state == .ended, !isDrawing else { return }
            parent.onThreeFingerTap?()
        }

        // Allow our taps to coexist with PencilKit's own gestures.
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        // MARK: Apple Pencil double-tap / squeeze → toggle eraser

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            parent.onPencilAction?()
        }

        @available(iOS 17.5, *)
        func pencilInteraction(_ interaction: UIPencilInteraction,
                               didReceiveTap tap: UIPencilInteraction.Tap) {
            parent.onPencilAction?()
        }

        @available(iOS 17.5, *)
        func pencilInteraction(_ interaction: UIPencilInteraction,
                               didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
            if squeeze.phase == .ended { parent.onPencilAction?() }
        }

        // MARK: Viewport reporting (zoom + scroll → SwiftUI layer images)

        func reportViewport(_ scrollView: UIScrollView) {
            let zoom = scrollView.zoomScale
            let offset = scrollView.contentOffset
            let change = parent.onViewportChange
            // Defer: these fire during layout/updateUIView, and publishing
            // SwiftUI state mid-update is undefined behavior.
            DispatchQueue.main.async { change?(zoom, offset) }
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { reportViewport(scrollView) }
        func scrollViewDidScroll(_ scrollView: UIScrollView) { reportViewport(scrollView) }

        // MARK: Pull past the edge → flip / create page

        /// The drag must travel well past the edge (against the rubber-band)
        /// before release; a casual scroll or flick never reaches this.
        private let pullThreshold: CGFloat = 110

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            pullFired = false
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            // Page pulls only at the fit scale — while zoomed in, panning past an
            // edge is navigation within the page, never a page flip.
            guard !pullFired, !isDrawing,
                  scrollView.zoomScale <= scrollView.minimumZoomScale * 1.02 else { return }
            let bottomOverscroll = scrollView.contentOffset.y + scrollView.bounds.height
                - max(scrollView.contentSize.height, scrollView.bounds.height)
            let topOverscroll = -(scrollView.contentOffset.y + scrollView.contentInset.top)
            if bottomOverscroll > pullThreshold {
                pullFired = true
                parent.onPullNext?()
            } else if topOverscroll > pullThreshold {
                pullFired = true
                parent.onPullPrevious?()
            }
        }

        // MARK: Drawing lifecycle

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            isDrawing = true
            // Palm rejection for the scroll view: while the tool is down a
            // resting palm must not pan/zoom the page.
            scrollReEnableWork?.cancel()
            canvasView.isScrollEnabled = false
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            isDrawing = false
            commit(canvasView)
            // Wait a short grace period before re-enabling scroll: between
            // strokes the pencil lifts for a fraction of a second while the palm
            // still rests on the glass.
            scrollReEnableWork?.cancel()
            let work = DispatchWorkItem { [weak canvasView] in
                canvasView?.isScrollEnabled = true
            }
            scrollReEnableWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // Ignore the continuous stream of changes WHILE a stroke is being
            // drawn: committing per segment churns the binding, the iPad side
            // panel (which observes the model) re-renders, and the re-entrant
            // updateUIView would cancel the live stroke. The finished stroke is
            // committed in canvasViewDidEndUsingTool. Changes that arrive when
            // NOT actively drawing (undo/redo, programmatic edits) commit here.
            guard !isDrawing, !isPullingIn else { return }
            commit(canvasView)
        }

        /// Apply symmetry (if any) and push the finished drawing up to the model.
        private func commit(_ canvasView: PKCanvasView) {
            guard !isApplyingSymmetry, !isPullingIn else { return }
            var newDrawing = canvasView.drawing

            // Mirror strokes added since the last commit.
            if parent.symmetry != .off, newDrawing.strokes.count > lastStrokeCount {
                let added = Array(newDrawing.strokes[lastStrokeCount...])
                let mirrored = SymmetryEngine.mirror(strokes: added,
                                                     mode: parent.symmetry,
                                                     canvasSize: parent.canvasSize)
                if !mirrored.isEmpty {
                    isApplyingSymmetry = true
                    newDrawing.strokes.append(contentsOf: mirrored)
                    canvasView.drawing = newDrawing
                    isApplyingSymmetry = false
                }
            }
            lastStrokeCount = newDrawing.strokes.count
            // Record what we pushed, then commit SYNCHRONOUSLY. An async commit
            // leaves a window where the canvas holds the finished stroke but the
            // binding still holds the previous value; a re-render in that window
            // makes updateUIView treat the stale binding as an external change
            // and reset the canvas — erasing the stroke (the "sometimes the
            // stroke disappears" bug). These callbacks are user-event driven
            // (touch-up / undo), so setting state synchronously is safe.
            lastPushedUp = newDrawing
            parent.drawing = newDrawing
        }
    }
}
