import SwiftUI
import CoreGraphics

/// The vector shapes the user can drop onto the canvas. Each shape is drawn by
/// dragging out a bounding rect, adjusted with draw-time handles (rotate / resize
/// / flip), then baked into the active layer's `PKDrawing` as one or more
/// `PKStroke`s — so the lasso, undo, delete and eraser all work on it exactly
/// like a freehand stroke.
enum ShapeKind: String, CaseIterable, Identifiable {
    case rectangle
    case ellipse
    case triangle
    case line

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .ellipse: return "Circle"
        case .triangle: return "Triangle"
        case .line: return "Line"
        }
    }

    var systemImage: String {
        switch self {
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .triangle: return "triangle"
        case .line: return "line.diagonal"
        }
    }

    /// A closed outline (rect / ellipse / triangle) can take a solid fill; an
    /// open line cannot.
    var canFill: Bool { self != .line }
}

/// Stroke + fill styling captured when a shape is committed.
struct ShapeStyle: Equatable {
    var strokeColor: Color
    var strokeWidth: CGFloat
    /// Solid fill colour, or `nil` for outline-only.
    var fillColor: Color?
}

/// A shape being drawn / adjusted before it is baked into the drawing. Geometry
/// is kept in **canvas** coordinates (the same space strokes live in), so the
/// editing overlay only has to scale by the display factor.
struct PendingShape: Equatable {
    var kind: ShapeKind
    /// Axis-aligned bounding rect in canvas coordinates.
    var rect: CGRect
    /// Rotation about the rect centre, in radians.
    var rotation: CGFloat = 0
    var flipH: Bool = false
    var flipV: Bool = false
    var style: ShapeStyle

    var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

    /// Normalised rect (non-negative width/height) so a drag in any direction
    /// produces a sane shape.
    var normalizedRect: CGRect { rect.standardized }
}
