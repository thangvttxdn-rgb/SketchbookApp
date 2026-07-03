import UIKit

/// Bucket / color-fill using a scanline flood fill on a rasterised snapshot of
/// the current artwork. Returns a transparent image containing only the filled
/// region, which the editor composites onto the active layer.
enum FloodFill {
    /// - Parameters:
    ///   - base: composited snapshot used to detect region boundaries.
    ///   - point: seed point in `base`'s pixel coordinate space.
    ///   - fillColor: the color to paint.
    ///   - tolerance: 0...1 color match tolerance.
    static func fill(in base: UIImage, at point: CGPoint, with fillColor: UIColor, tolerance: CGFloat = 0.12) -> UIImage? {
        guard let cg = base.cgImage else { return nil }
        let width = cg.width, height = cg.height
        let sx = Int(point.x), sy = Int(point.y)
        guard sx >= 0, sy >= 0, sx < width, sy < height else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var src = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let ctx = CGContext(data: &src, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        let seed = (sy * width + sx) * bytesPerPixel
        let target = (src[seed], src[seed + 1], src[seed + 2], src[seed + 3])
        let tol = Int16(tolerance * 255)

        // Output buffer (transparent) we paint into.
        var out = [UInt8](repeating: 0, count: bytesPerRow * height)
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        fillColor.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        let cr = UInt8(fr * 255), cg2 = UInt8(fg * 255), cb = UInt8(fb * 255), ca = UInt8(fa * 255)

        // Scanline span fill over raw buffers: fills whole horizontal runs and
        // pushes at most one seed per run above/below — orders of magnitude
        // fewer stack operations and bounds checks than a per-pixel fill (the
        // old version took seconds on a 2048×1536 canvas).
        var visited = [Bool](repeating: false, count: width * height)
        src.withUnsafeBufferPointer { sp in
            out.withUnsafeMutableBufferPointer { op in
                visited.withUnsafeMutableBufferPointer { vp in
                    @inline(__always) func matches(_ x: Int, _ y: Int) -> Bool {
                        let p = (y * width + x) * bytesPerPixel
                        return abs(Int16(sp[p]) - Int16(target.0)) <= tol
                            && abs(Int16(sp[p + 1]) - Int16(target.1)) <= tol
                            && abs(Int16(sp[p + 2]) - Int16(target.2)) <= tol
                            && abs(Int16(sp[p + 3]) - Int16(target.3)) <= tol
                    }
                    var stack: [(Int, Int)] = [(sx, sy)]
                    stack.reserveCapacity(4096)
                    while let (x, y) = stack.popLast() {
                        if vp[y * width + x] || !matches(x, y) { continue }
                        // Expand the run left and right.
                        var lx = x
                        while lx > 0, !vp[y * width + lx - 1], matches(lx - 1, y) { lx -= 1 }
                        var rx = x
                        while rx < width - 1, !vp[y * width + rx + 1], matches(rx + 1, y) { rx += 1 }
                        // Paint + mark the run.
                        for xi in lx...rx {
                            vp[y * width + xi] = true
                            let p = (y * width + xi) * bytesPerPixel
                            op[p] = cr; op[p + 1] = cg2; op[p + 2] = cb; op[p + 3] = ca
                        }
                        // Seed one entry per matching run in the rows above/below.
                        for ny in [y - 1, y + 1] where ny >= 0 && ny < height {
                            var xi = lx
                            while xi <= rx {
                                if !vp[ny * width + xi], matches(xi, ny) {
                                    stack.append((xi, ny))
                                    while xi <= rx, matches(xi, ny) { xi += 1 }
                                } else {
                                    xi += 1
                                }
                            }
                        }
                    }
                }
            }
        }

        guard let outCtx = CGContext(data: &out, width: width, height: height, bitsPerComponent: 8,
                                     bytesPerRow: bytesPerRow, space: colorSpace,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let outCG = outCtx.makeImage() else { return nil }
        return UIImage(cgImage: outCG, scale: base.scale, orientation: .up)
    }
}
