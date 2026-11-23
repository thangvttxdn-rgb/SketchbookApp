import SwiftUI
import CoreGraphics

/// The vector shapes the user can drop onto the canvas. Each shape is drawn by
/// dragging out a bounding rect, adjusted with draw-time handles (rotate / resize
/// / flip), then baked into the active layer's `PKDrawing` as one or more
/// `PKStroke`s — so the lasso, undo, delete and eraser all work on it exactly
/// like a freehand stroke.
enum ShapeKind: String, CaseIterable, Identifiable, Codable {
    case rectangle
    case ellipse
    case triangle
    case diamond
    case star
    case pentagon
    case hexagon
    case arrow
    case heart
    case line
    case dimension   // vẽ kỹ thuật: đường ghi kích thước (2 mũi tên + số mm)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rectangle: return "Hình chữ nhật"
        case .ellipse: return "Hình tròn"
        case .triangle: return "Tam giác"
        case .diamond: return "Hình thoi"
        case .star: return "Ngôi sao"
        case .pentagon: return "Ngũ giác"
        case .hexagon: return "Lục giác"
        case .arrow: return "Mũi tên"
        case .heart: return "Trái tim"
        case .line: return "Đoạn thẳng"
        case .dimension: return "Ghi kích thước"
        }
    }

    var systemImage: String {
        switch self {
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .triangle: return "triangle"
        case .diamond: return "diamond"
        case .star: return "star"
        case .pentagon: return "pentagon"
        case .hexagon: return "hexagon"
        case .arrow: return "arrow.right"
        case .heart: return "heart"
        case .line: return "line.diagonal"
        case .dimension: return "ruler"
        }
    }

    /// A closed outline can take a solid fill; an open line cannot.
    var canFill: Bool { !isLinear }

    /// Open, two-point kinds drawn along the bounding-rect diagonal.
    var isLinear: Bool { self == .line || self == .dimension }
}

/// A vector shape already baked into a layer, kept alongside the strokes so the
/// fill tool can later tap-to-fill it (hit-test + regenerate a crisp vector fill)
/// even after it has become plain ink. Geometry is in canvas coordinates.
struct PlacedShape: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: ShapeKind
    /// Normalised (standardized) bounding rect in canvas coordinates.
    var rect: CGRect
    /// Rotation about the rect centre, in radians.
    var rotation: CGFloat = 0
    var flipH: Bool = false
    var flipV: Bool = false
    /// Outline style, kept so a later tap-to-fill can redraw the outline on top.
    var strokeColorHex: String
    var strokeWidth: CGFloat

    var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
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
