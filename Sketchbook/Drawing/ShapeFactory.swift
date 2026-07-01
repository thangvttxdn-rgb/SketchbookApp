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
        if shape.kind.canFill, let fill = shape.style.fillColor,
           let fillStroke = fillStroke(kind: shape.kind, rect: rect, color: UIColor(fill)) {
            strokes.append(fillStroke)
        }

        // Outline.
        let outlinePoints = outlinePoints(kind: shape.kind, rect: rect)
        if outlinePoints.count >= 2 {
            let stroke = makeStroke(points: outlinePoints,
                                    color: UIColor(shape.style.strokeColor),
                                    width: max(1, shape.style.strokeWidth))
            strokes.append(stroke)
        }

        // Rotate / flip about the shape centre.
        let t = transform(around: shape.center,
                          angle: shape.rotation, flipH: shape.flipH, flipV: shape.flipV)
        return strokes.map { stroke in
            var copy = stroke
            copy.transform = stroke.transform.concatenating(t)
            return copy
        }
    }

    // MARK: - Outline geometry

    private static func outlinePoints(kind: ShapeKind, rect: CGRect) -> [CGPoint] {
        switch kind {
        case .line:
            // Top-left → bottom-right diagonal of the (normalised) bounding rect,
            // matching the on-screen preview.
            return [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY)]
        case .rectangle:
            let v = [CGPoint(x: rect.minX, y: rect.minY),
                     CGPoint(x: rect.maxX, y: rect.minY),
                     CGPoint(x: rect.maxX, y: rect.maxY),
                     CGPoint(x: rect.minX, y: rect.maxY)]
            return polygon(v)
        case .triangle:
            let v = [CGPoint(x: rect.midX, y: rect.minY),
                     CGPoint(x: rect.maxX, y: rect.maxY),
                     CGPoint(x: rect.minX, y: rect.maxY)]
            return polygon(v)
        case .ellipse:
            return ellipse(rect)
        }
    }

    /// Walk a closed polygon, sampling each edge densely and pinning every vertex
    /// (repeated 3×) so `PKStrokePath`'s spline keeps the corners sharp.
    private static func polygon(_ verts: [CGPoint], spacing: CGFloat = 4) -> [CGPoint] {
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

    // MARK: - Solid fill (serpentine scanline)

    private static func fillStroke(kind: ShapeKind, rect: CGRect, color: UIColor) -> PKStroke? {
        guard rect.height > 1, rect.width > 1 else { return nil }
        var pts: [CGPoint] = []
        var leftToRight = true
        var y = rect.minY + fillSpacing / 2
        while y <= rect.maxY {
            if let (x0, x1) = xSpan(kind: kind, rect: rect, y: y), x1 > x0 {
                if leftToRight { pts.append(CGPoint(x: x0, y: y)); pts.append(CGPoint(x: x1, y: y)) }
                else { pts.append(CGPoint(x: x1, y: y)); pts.append(CGPoint(x: x0, y: y)) }
                leftToRight.toggle()
            }
            y += fillSpacing
        }
        guard pts.count >= 2 else { return nil }
        return makeStroke(points: pts, color: color, width: fillSpacing * 1.15)
    }

    /// Horizontal interior span of the shape at scanline `y`, or `nil` if the row
    /// lies outside the shape.
    private static func xSpan(kind: ShapeKind, rect: CGRect, y: CGFloat) -> (CGFloat, CGFloat)? {
        switch kind {
        case .rectangle, .line:
            return (rect.minX, rect.maxX)
        case .triangle:
            // Apex at top-centre, base along the bottom edge.
            let t = (y - rect.minY) / max(rect.height, 0.0001)
            let leftX = rect.midX + (rect.minX - rect.midX) * t
            let rightX = rect.midX + (rect.maxX - rect.midX) * t
            return (leftX, rightX)
        case .ellipse:
            let cy = rect.midY, ry = rect.height / 2
            let dy = y - cy
            guard abs(dy) <= ry else { return nil }
            let dx = rect.width / 2 * sqrt(max(0, 1 - (dy / ry) * (dy / ry)))
            return (rect.midX - dx, rect.midX + dx)
        }
    }

    // MARK: - PKStroke construction

    private static func makeStroke(points: [CGPoint], color: UIColor, width: CGFloat) -> PKStroke {
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

    /// Rotate by `angle` (radians) and optionally flip about `center`.
    private static func transform(around center: CGPoint, angle: CGFloat,
                                  flipH: Bool, flipV: Bool) -> CGAffineTransform {
        let sx: CGFloat = flipH ? -1 : 1
        let sy: CGFloat = flipV ? -1 : 1
        return CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: angle)
            .scaledBy(x: sx, y: sy)
            .translatedBy(x: -center.x, y: -center.y)
    }
}
