import PencilKit
import SwiftUI
import UIKit

/// Builds a `PendingShape` into `PKStroke`s that are appended to the active
/// layer's drawing. Everything is a stroke — outline *and* fill — so once baked
/// the shape behaves exactly like freehand ink under the lasso, eraser and undo.
///
/// Geometry is authored axis-aligned in canvas coordinates; rotation and flip are
/// applied through each stroke's affine `transform` (the same mechanism
/// `SymmetryEngine` uses to mirror strokes), which keeps stroke width undistorted.
enum ShapeFactory {

    /// Fill scanline spacing (canvas px). Rows overlap slightly so there are no gaps.
    private static let fillSpacing: CGFloat = 6

    /// Produce the strokes for a shape — fill first (so the outline draws on top),
    /// then the outline. Empty rects produce nothing.
    static func strokes(for shape: PendingShape) -> [PKStroke] {
        let rect = shape.normalizedRect
        guard rect.width > 1 || rect.height > 1 else { return [] }

        var strokes: [PKStroke] = []

        // Fill (closed shapes only).
        if shape.kind.canFill, let fill = shape.style.fillColor {
            strokes.append(contentsOf: fillStrokes(kind: shape.kind, rect: rect, color: UIColor(fill)))
        }

        // Outline.
        if let stroke = outlineStroke(kind: shape.kind, rect: rect,
                                      color: UIColor(shape.style.strokeColor),
                                      width: shape.style.strokeWidth) {
            strokes.append(stroke)
        }

        // Dimension line: arrowheads at both ends.
        if shape.kind == .dimension {
            let a = CGPoint(x: rect.minX, y: rect.minY), b = CGPoint(x: rect.maxX, y: rect.maxY)
            let size = max(18, shape.style.strokeWidth * 4)
            let color = UIColor(shape.style.strokeColor)
            for (tip, from) in [(a, b), (b, a)] {
                strokes.append(makeStroke(points: arrowhead(tip: tip, from: from, size: size),
                                          color: color, width: max(1, shape.style.strokeWidth)))
            }
        }

        // Rotate / flip about the shape centre.
        let t = transform(around: shape.center,
                          angle: shape.rotation, flipH: shape.flipH, flipV: shape.flipV)
        return strokes.map { applying(t, to: $0) }
    }

    /// End points (canvas coords, after rotate/flip) of a linear shape.
    static func endpoints(of shape: PendingShape) -> (CGPoint, CGPoint) {
        let rect = shape.normalizedRect
        let t = transform(around: shape.center,
                          angle: shape.rotation, flipH: shape.flipH, flipV: shape.flipV)
        return (CGPoint(x: rect.minX, y: rect.minY).applying(t),
                CGPoint(x: rect.maxX, y: rect.maxY).applying(t))
    }

    /// Open "V" arrowhead at `tip`, pointing away from `from`. The tip vertex is
    /// repeated so the stroke spline keeps it sharp.
    private static func arrowhead(tip: CGPoint, from: CGPoint, size: CGFloat) -> [CGPoint] {
        let angle = atan2(from.y - tip.y, from.x - tip.x)
        let spread: CGFloat = .pi / 9   // 20°
        let p1 = CGPoint(x: tip.x + size * cos(angle + spread), y: tip.y + size * sin(angle + spread))
        let p2 = CGPoint(x: tip.x + size * cos(angle - spread), y: tip.y + size * sin(angle - spread))
        return [p1, tip, tip, tip, p2]
    }

    /// Fill + refreshed outline for a shape that is already baked into a layer
    /// (the fill tool's tap-to-fill). The outline is re-appended on top so it
    /// stays visible over the new fill.
    static func refillStrokes(for placed: PlacedShape, fillColor: UIColor) -> [PKStroke] {
        let rect = placed.rect.standardized
        guard placed.kind.canFill, rect.width > 1, rect.height > 1 else { return [] }
        var strokes = fillStrokes(kind: placed.kind, rect: rect, color: fillColor)
        if let outline = outlineStroke(kind: placed.kind, rect: rect,
                                       color: UIColor(hex: placed.strokeColorHex),
                                       width: placed.strokeWidth) {
            strokes.append(outline)
        }
        let t = transform(around: placed.center,
                          angle: placed.rotation, flipH: placed.flipH, flipV: placed.flipV)
        return strokes.map { applying(t, to: $0) }
    }

    /// Whether a canvas-space point lands inside the placed shape (used by the
    /// fill tool to decide vector fill vs. raster flood fill).
    static func hitTest(_ placed: PlacedShape, point: CGPoint) -> Bool {
        guard placed.kind.canFill else { return false }
        let rect = placed.rect.standardized
        guard rect.width > 1, rect.height > 1 else { return false }
        // Invert the commit transform: p = c + S(R(-angle)(q - c)).
        let c = placed.center
        var v = CGVector(dx: point.x - c.x, dy: point.y - c.y)
        let a = -placed.rotation
        v = CGVector(dx: v.dx * cos(a) - v.dy * sin(a), dy: v.dx * sin(a) + v.dy * cos(a))
        if placed.flipH { v.dx = -v.dx }
        if placed.flipV { v.dy = -v.dy }
        let local = CGPoint(x: c.x + v.dx, y: c.y + v.dy)

        switch placed.kind {
        case .ellipse:
            let dx = (local.x - rect.midX) / max(rect.width / 2, 0.0001)
            let dy = (local.y - rect.midY) / max(rect.height / 2, 0.0001)
            return dx * dx + dy * dy <= 1
        case .rectangle:
            return rect.contains(local)
        default:
            let verts = polygonVertices(kind: placed.kind, rect: rect)
            return contains(polygon: verts, point: local)
        }
    }

    // MARK: - Outline geometry

    private static func outlineStroke(kind: ShapeKind, rect: CGRect,
                                      color: UIColor, width: CGFloat) -> PKStroke? {
        let points = outlinePoints(kind: kind, rect: rect)
        guard points.count >= 2 else { return nil }
        return makeStroke(points: points, color: color, width: max(1, width))
    }

    private static func outlinePoints(kind: ShapeKind, rect: CGRect) -> [CGPoint] {
        switch kind {
        case .line, .dimension:
            // Top-left → bottom-right diagonal of the (normalised) bounding rect,
            // matching the on-screen preview.
            return [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY)]
        case .ellipse:
            return ellipse(rect)
        default:
            return polygon(polygonVertices(kind: kind, rect: rect))
        }
    }

    /// Vertex list (canvas coords) for every polygonal shape kind. The heart is
    /// a densely sampled parametric curve treated as a polygon.
    static func polygonVertices(kind: ShapeKind, rect: CGRect) -> [CGPoint] {
        switch kind {
        case .rectangle:
            return [CGPoint(x: rect.minX, y: rect.minY),
                    CGPoint(x: rect.maxX, y: rect.minY),
                    CGPoint(x: rect.maxX, y: rect.maxY),
                    CGPoint(x: rect.minX, y: rect.maxY)]
        case .triangle:
            return [CGPoint(x: rect.midX, y: rect.minY),
                    CGPoint(x: rect.maxX, y: rect.maxY),
                    CGPoint(x: rect.minX, y: rect.maxY)]
        case .diamond:
            return [CGPoint(x: rect.midX, y: rect.minY),
                    CGPoint(x: rect.maxX, y: rect.midY),
                    CGPoint(x: rect.midX, y: rect.maxY),
                    CGPoint(x: rect.minX, y: rect.midY)]
        case .star:
            return starVertices(points: 5, innerRatio: 0.42, in: rect)
        case .pentagon:
            return regularVertices(sides: 5, in: rect)
        case .hexagon:
            return regularVertices(sides: 6, in: rect)
        case .arrow:
            // Right-pointing arrow: shaft + triangular head.
            let cy = rect.midY
            let headX = rect.minX + rect.width * 0.62
            let shaft = rect.height * 0.18
            return [CGPoint(x: rect.minX, y: cy - shaft),
                    CGPoint(x: headX, y: cy - shaft),
                    CGPoint(x: headX, y: rect.minY),
                    CGPoint(x: rect.maxX, y: cy),
                    CGPoint(x: headX, y: rect.maxY),
                    CGPoint(x: headX, y: cy + shaft),
                    CGPoint(x: rect.minX, y: cy + shaft)]
        case .heart:
            return heartVertices(in: rect)
        case .ellipse, .line, .dimension:
            return []
        }
    }

    /// Star with alternating outer/inner radii, apex pointing up.
    static func starVertices(points: Int, innerRatio: CGFloat, in rect: CGRect) -> [CGPoint] {
        let cx = rect.midX, cy = rect.midY
        let rx = rect.width / 2, ry = rect.height / 2
        var verts: [CGPoint] = []
        for i in 0..<(points * 2) {
            let r: CGFloat = i.isMultiple(of: 2) ? 1 : innerRatio
            let theta = -CGFloat.pi / 2 + CGFloat(i) * .pi / CGFloat(points)
            verts.append(CGPoint(x: cx + rx * r * cos(theta), y: cy + ry * r * sin(theta)))
        }
        return verts
    }

    private static func regularVertices(sides: Int, in rect: CGRect) -> [CGPoint] {
        let cx = rect.midX, cy = rect.midY
        let rx = rect.width / 2, ry = rect.height / 2
        return (0..<sides).map { i in
            let theta = -CGFloat.pi / 2 + CGFloat(i) * 2 * .pi / CGFloat(sides)
            return CGPoint(x: cx + rx * cos(theta), y: cy + ry * sin(theta))
        }
    }

    /// Classic parametric heart, sampled and normalised into `rect`.
    private static func heartVertices(in rect: CGRect, samples: Int = 96) -> [CGPoint] {
        var raw: [CGPoint] = []
        raw.reserveCapacity(samples)
        for i in 0..<samples {
            let t = 2 * CGFloat.pi * CGFloat(i) / CGFloat(samples)
            let x = 16 * pow(sin(t), 3)
            let y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
            raw.append(CGPoint(x: x, y: -y))   // flip so the point is at the bottom
        }
        let minX = raw.map(\.x).min() ?? 0, maxX = raw.map(\.x).max() ?? 1
        let minY = raw.map(\.y).min() ?? 0, maxY = raw.map(\.y).max() ?? 1
        let w = max(maxX - minX, 0.0001), h = max(maxY - minY, 0.0001)
        return raw.map { p in
            CGPoint(x: rect.minX + (p.x - minX) / w * rect.width,
                    y: rect.minY + (p.y - minY) / h * rect.height)
        }
    }

    /// Walk a closed polygon, sampling each edge densely and pinning every vertex
    /// (repeated 3×) so `PKStrokePath`'s spline keeps the corners sharp.
    private static func polygon(_ verts: [CGPoint], spacing: CGFloat = 4) -> [CGPoint] {
        guard verts.count >= 2 else { return [] }
        var pts: [CGPoint] = []
        let n = verts.count
        for i in 0..<n {
            let a = verts[i]
            let b = verts[(i + 1) % n]
            pts.append(a); pts.append(a); pts.append(a)   // pin the vertex
            let dist = hypot(b.x - a.x, b.y - a.y)
            let steps = max(1, Int(dist / spacing))
            for s in 1..<steps {
                let f = CGFloat(s) / CGFloat(steps)
                pts.append(CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f))
            }
        }
        // Close the loop back onto the first vertex.
        let f = verts[0]
        pts.append(f); pts.append(f); pts.append(f)
        return pts
    }

    private static func ellipse(_ rect: CGRect, samples: Int = 144) -> [CGPoint] {
        let cx = rect.midX, cy = rect.midY
        let rx = rect.width / 2, ry = rect.height / 2
        var pts: [CGPoint] = []
        pts.reserveCapacity(samples + 1)
        for i in 0...samples {
            let theta = 2 * CGFloat.pi * CGFloat(i) / CGFloat(samples)
            pts.append(CGPoint(x: cx + rx * cos(theta), y: cy + ry * sin(theta)))
        }
        return pts
    }

    // MARK: - Solid fill (even-odd multi-span scanline)

    /// Fill a shape with horizontal serpentine strokes. Concave shapes (star,
    /// arrow, heart) produce multiple spans per scanline; contiguous bands with
    /// the same span count are merged into one serpentine stroke per span so the
    /// stroke count stays small.
    static func fillStrokes(kind: ShapeKind, rect: CGRect, color: UIColor,
                            spacing: CGFloat? = nil) -> [PKStroke] {
        guard rect.height > 1, rect.width > 1 else { return [] }
        let gap = spacing ?? fillSpacing
        return bandedFill(minY: rect.minY, maxY: rect.maxY, gap: gap, color: color) { y in
            spans(kind: kind, rect: rect, y: y)
        }
    }

    /// Fill an arbitrary closed polygon (used by the Stardust brush's stars).
    static func fillStrokes(vertices: [CGPoint], color: UIColor, spacing: CGFloat) -> [PKStroke] {
        guard vertices.count >= 3 else { return [] }
        let minY = vertices.map(\.y).min() ?? 0
        let maxY = vertices.map(\.y).max() ?? 0
        guard maxY - minY > 0.5 else { return [] }
        return bandedFill(minY: minY, maxY: maxY, gap: spacing, color: color) { y in
            polygonSpans(vertices, y: y)
        }
    }

    private static func bandedFill(minY: CGFloat, maxY: CGFloat, gap: CGFloat, color: UIColor,
                                   spansAt: (CGFloat) -> [(CGFloat, CGFloat)]) -> [PKStroke] {
        let width = gap * 1.15
        let capR = width / 2   // round-cap radius past each endpoint
        var strokes: [PKStroke] = []
        var active: [[CGPoint]] = []

        func flush() {
            for pts in active where pts.count >= 2 {
                strokes.append(makeStroke(points: pts, color: color, width: width))
            }
            active = []
        }

        // PKStrokePath fits a spline through the points, which rounds the turn
        // between rows and leaves alternating rows short of the edge (a visible
        // comb pattern). Pin every row endpoint (repeat 3×) so corners stay
        // square, and pull endpoints in by the cap radius so the round caps
        // land exactly on the span edge.
        func appendRow(_ i: Int, from a: CGFloat, to b: CGFloat, y: CGFloat) {
            let p0 = CGPoint(x: a, y: y), p1 = CGPoint(x: b, y: y)
            active[i].append(contentsOf: [p0, p0, p0, p1, p1, p1])
        }

        var leftToRight = true
        var y = minY + gap / 2
        while y <= maxY {
            let rowSpans = spansAt(y).filter { $0.1 - $0.0 > 0.3 }
            if rowSpans.count != active.count {
                flush()
                active = Array(repeating: [], count: rowSpans.count)
            }
            for (i, span) in rowSpans.enumerated() {
                var (x0, x1) = span
                if x1 - x0 > width { x0 += capR; x1 -= capR }   // caps finish the ends
                else { let mid = (x0 + x1) / 2; x0 = mid; x1 = mid }
                if leftToRight { appendRow(i, from: x0, to: x1, y: y) }
                else { appendRow(i, from: x1, to: x0, y: y) }
            }
            leftToRight.toggle()
            y += gap
        }
        flush()
        return strokes
    }

    /// Interior x-spans of the shape at scanline `y`, sorted left to right.
    private static func spans(kind: ShapeKind, rect: CGRect, y: CGFloat) -> [(CGFloat, CGFloat)] {
        switch kind {
        case .rectangle, .line, .dimension:
            return [(rect.minX, rect.maxX)]
        case .ellipse:
            let cy = rect.midY, ry = rect.height / 2
            let dy = y - cy
            guard abs(dy) <= ry, ry > 0 else { return [] }
            let dx = rect.width / 2 * sqrt(max(0, 1 - (dy / ry) * (dy / ry)))
            return [(rect.midX - dx, rect.midX + dx)]
        default:
            return polygonSpans(polygonVertices(kind: kind, rect: rect), y: y)
        }
    }

    /// Even-odd intersection of a horizontal scanline with a closed polygon.
    private static func polygonSpans(_ verts: [CGPoint], y: CGFloat) -> [(CGFloat, CGFloat)] {
        guard verts.count >= 3 else { return [] }
        var xs: [CGFloat] = []
        let n = verts.count
        for i in 0..<n {
            let a = verts[i], b = verts[(i + 1) % n]
            if (a.y <= y && b.y > y) || (b.y <= y && a.y > y) {
                xs.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
            }
        }
        xs.sort()
        var result: [(CGFloat, CGFloat)] = []
        var i = 0
        while i + 1 < xs.count {
            result.append((xs[i], xs[i + 1]))
            i += 2
        }
        return result
    }

    /// Even-odd point-in-polygon test.
    static func contains(polygon verts: [CGPoint], point: CGPoint) -> Bool {
        guard verts.count >= 3 else { return false }
        var inside = false
        let n = verts.count
        for i in 0..<n {
            let a = verts[i], b = verts[(i + 1) % n]
            if (a.y <= point.y && b.y > point.y) || (b.y <= point.y && a.y > point.y) {
                let x = a.x + (point.y - a.y) / (b.y - a.y) * (b.x - a.x)
                if x > point.x { inside.toggle() }
            }
        }
        return inside
    }

    // MARK: - PKStroke construction

    static func makeStroke(points: [CGPoint], color: UIColor, width: CGFloat) -> PKStroke {
        let dt = 1.0 / 240.0
        let strokePoints: [PKStrokePoint] = points.enumerated().map { i, p in
            PKStrokePoint(location: p,
                          timeOffset: Double(i) * dt,
                          size: CGSize(width: width, height: width),
                          opacity: 1,
                          force: 1,
                          azimuth: 0,
                          altitude: .pi / 2)
        }
        let path = PKStrokePath(controlPoints: strokePoints, creationDate: Date())
        // .pen gives crisp, opaque geometry with a wide valid width range; the
        // ink carries type + colour, the per-point `size` carries the thickness.
        let ink = PKInkingTool(.pen, color: color, width: max(1, width)).ink
        return PKStroke(ink: ink, path: path)
    }

    static func applying(_ t: CGAffineTransform, to stroke: PKStroke) -> PKStroke {
        var copy = stroke
        copy.transform = stroke.transform.concatenating(t)
        return copy
    }

    /// Rotate by `angle` (radians) and optionally flip about `center`.
    static func transform(around center: CGPoint, angle: CGFloat,
                          flipH: Bool, flipV: Bool) -> CGAffineTransform {
        let sx: CGFloat = flipH ? -1 : 1
        let sy: CGFloat = flipV ? -1 : 1
        return CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: angle)
            .scaledBy(x: sx, y: sy)
            .translatedBy(x: -center.x, y: -center.y)
    }
}
