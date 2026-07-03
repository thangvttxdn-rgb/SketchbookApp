import PencilKit
import SwiftUI
import UIKit

/// One sprinkled particle of the Stardust brush — a little star or a dust dot,
/// in canvas coordinates.
struct StardustStamp: Identifiable, Equatable {
    enum Kind: Equatable { case dot, sparkle, star }
    let id = UUID()
    var kind: Kind
    var center: CGPoint
    var size: CGFloat
    var rotation: CGFloat
    var alpha: CGFloat
}

/// The Stardust brush: dragging on the canvas scatters little stars and dust
/// dots along the path with random size / rotation / jitter. While the drag is
/// live the stamps render in a SwiftUI overlay; on release they are baked into
/// the active layer's `PKDrawing` as strokes — so undo, lasso and the eraser
/// treat the sprinkle exactly like ink.
enum Stardust {

    /// Hard cap so one long scrub can't produce an unmanageable drawing.
    static let maxStampsPerStroke = 300

    /// Scatter stamps between two drag points. `brushSize` is in canvas px.
    static func scatter(from previous: CGPoint?, to point: CGPoint,
                        brushSize: CGFloat) -> [StardustStamp] {
        let spacing = max(brushSize * 1.1, 8)
        var out: [StardustStamp] = []
        guard let prev = previous else {
            out.append(contentsOf: burst(at: point, brushSize: brushSize))
            return out
        }
        let dist = hypot(point.x - prev.x, point.y - prev.y)
        guard dist >= spacing else { return [] }
        let steps = min(Int(dist / spacing), 8)
        for s in 1...max(steps, 1) {
            let f = CGFloat(s) / CGFloat(max(steps, 1))
            let p = CGPoint(x: prev.x + (point.x - prev.x) * f,
                            y: prev.y + (point.y - prev.y) * f)
            out.append(contentsOf: burst(at: p, brushSize: brushSize))
        }
        return out
    }

    /// A sparse sprinkle around one path point: mostly tiny dust dots plus the
    /// occasional star. Kept sparse and spread wide so particles read
    /// individually instead of clumping into blobs.
    private static func burst(at p: CGPoint, brushSize: CGFloat) -> [StardustStamp] {
        var stamps: [StardustStamp] = []
        let jitterR = brushSize * 2.2
        let count = Int.random(in: 1...2)
        for _ in 0..<count {
            let angle = CGFloat.random(in: 0..<(2 * .pi))
            // sqrt-free bias outward so particles don't pile up at the centre.
            let radius = jitterR * CGFloat.random(in: 0.15...1.0)
            let c = CGPoint(x: p.x + radius * cos(angle), y: p.y + radius * sin(angle))
            let roll = CGFloat.random(in: 0...1)
            let kind: StardustStamp.Kind = roll < 0.5 ? .dot : (roll < 0.85 ? .sparkle : .star)
            let size: CGFloat
            switch kind {
            case .dot: size = brushSize * CGFloat.random(in: 0.06...0.16)
            case .sparkle: size = brushSize * CGFloat.random(in: 0.45...0.9)
            case .star: size = brushSize * CGFloat.random(in: 0.6...1.2)
            }
            stamps.append(StardustStamp(kind: kind,
                                        center: c,
                                        size: max(size, 2),
                                        rotation: CGFloat.random(in: -0.6...0.6),
                                        alpha: CGFloat.random(in: 0.35...1.0)))
        }
        return stamps
    }

    /// Bake stamps into PencilKit strokes. Dots are single fat points; sparkles
    /// and stars are crossing TAPERED strokes (wide centre → hairline tips),
    /// which read as crisp twinkles at any size — a scanline fill this small
    /// just smudges.
    static func strokes(for stamps: [StardustStamp], color: UIColor) -> [PKStroke] {
        var strokes: [PKStroke] = []
        for stamp in stamps {
            let c = color.withAlphaComponent(alphaOf(color) * stamp.alpha)
            switch stamp.kind {
            case .dot:
                strokes.append(ShapeFactory.makeStroke(
                    points: [stamp.center, stamp.center], color: c, width: stamp.size))
            case .sparkle:
                // 4-ray twinkle: a long vertical spike crossed by a shorter one.
                strokes.append(taperedRay(center: stamp.center, length: stamp.size,
                                          angle: stamp.rotation + .pi / 2,
                                          maxWidth: stamp.size * 0.22, color: c))
                strokes.append(taperedRay(center: stamp.center, length: stamp.size * 0.7,
                                          angle: stamp.rotation,
                                          maxWidth: stamp.size * 0.18, color: c))
            case .star:
                // 6-ray star: three crossing spikes.
                for i in 0..<3 {
                    strokes.append(taperedRay(center: stamp.center, length: stamp.size,
                                              angle: stamp.rotation + CGFloat(i) * .pi / 3,
                                              maxWidth: stamp.size * 0.16, color: c))
                }
            }
        }
        return strokes
    }

    /// One spike through `center`: hairline at both tips, `maxWidth` in the middle.
    private static func taperedRay(center: CGPoint, length: CGFloat, angle: CGFloat,
                                   maxWidth: CGFloat, color: UIColor) -> PKStroke {
        let dir = CGVector(dx: cos(angle), dy: sin(angle))
        let half = length / 2
        let samples = 9
        let dt = 1.0 / 240.0
        let points: [PKStrokePoint] = (0..<samples).map { i in
            let t = CGFloat(i) / CGFloat(samples - 1) * 2 - 1   // -1 ... 1
            let p = CGPoint(x: center.x + dir.dx * half * t,
                            y: center.y + dir.dy * half * t)
            let w = max(maxWidth * pow(1 - abs(t), 1.6), 1.2)
            return PKStrokePoint(location: p, timeOffset: Double(i) * dt,
                                 size: CGSize(width: w, height: w),
                                 opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        let ink = PKInkingTool(.pen, color: color, width: maxWidth).ink
        return PKStroke(ink: ink, path: path)
    }

    /// SwiftUI path for the live preview overlay (display coordinates), matching
    /// the baked spike geometry.
    static func previewPath(for stamp: StardustStamp, scale: CGFloat) -> Path {
        let size = stamp.size * scale
        let c = CGPoint(x: stamp.center.x * scale, y: stamp.center.y * scale)
        var p = Path()
        switch stamp.kind {
        case .dot:
            p.addEllipse(in: CGRect(x: c.x - size / 2, y: c.y - size / 2, width: size, height: size))
        case .sparkle:
            addSpike(&p, center: c, length: size, angle: stamp.rotation + .pi / 2, width: size * 0.22)
            addSpike(&p, center: c, length: size * 0.7, angle: stamp.rotation, width: size * 0.18)
        case .star:
            for i in 0..<3 {
                addSpike(&p, center: c, length: size,
                         angle: stamp.rotation + CGFloat(i) * .pi / 3, width: size * 0.16)
            }
        }
        return p
    }

    /// A slender diamond approximating one tapered ray.
    private static func addSpike(_ p: inout Path, center: CGPoint, length: CGFloat,
                                 angle: CGFloat, width: CGFloat) {
        let dir = CGVector(dx: cos(angle), dy: sin(angle))
        let norm = CGVector(dx: -dir.dy, dy: dir.dx)
        let half = length / 2, hw = max(width / 2, 0.6)
        p.move(to: CGPoint(x: center.x + dir.dx * half, y: center.y + dir.dy * half))
        p.addLine(to: CGPoint(x: center.x + norm.dx * hw, y: center.y + norm.dy * hw))
        p.addLine(to: CGPoint(x: center.x - dir.dx * half, y: center.y - dir.dy * half))
        p.addLine(to: CGPoint(x: center.x - norm.dx * hw, y: center.y - norm.dy * hw))
        p.closeSubpath()
    }

    private static func alphaOf(_ color: UIColor) -> CGFloat {
        var a: CGFloat = 1
        color.getRed(nil, green: nil, blue: nil, alpha: &a)
        return a
    }
}
