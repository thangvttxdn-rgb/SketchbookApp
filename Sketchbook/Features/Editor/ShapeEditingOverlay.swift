import SwiftUI

/// Draw-time editor for a `PendingShape`: renders the live shape with a rotated
/// selection box, four corner resize handles (symmetric about the centre), a
/// rotate handle, and a floating bar to flip / confirm / cancel. All geometry is
/// kept in canvas coordinates on the view model; this overlay only scales by the
/// display `scale` to draw, and divides drag translations by `scale` to write back.
struct ShapeEditingOverlay: View {
    @ObservedObject var vm: EditorViewModel
    /// canvas → display scale factor.
    let scale: CGFloat
    /// Display size of the canvas (the overlay frame).
    let displaySize: CGSize

    /// Shape captured at the start of a drag so deltas are absolute.
    @State private var dragStart: PendingShape?

    private let handleSize: CGFloat = 22

    private enum Corner: CaseIterable { case topLeft, topRight, bottomRight, bottomLeft
        var sign: (CGFloat, CGFloat) {
            switch self {
            case .topLeft: return (-1, -1)
            case .topRight: return (1, -1)
            case .bottomRight: return (1, 1)
            case .bottomLeft: return (-1, 1)
            }
        }
    }

    var body: some View {
        if let shape = vm.pendingShape {
            ZStack(alignment: .topLeading) {
                shapePreview(shape)
                selectionBox(shape)
                if shape.kind == .dimension { measurementBadge(shape) }
                ForEach(Array(Corner.allCases.enumerated()), id: \.offset) { _, corner in
                    handle(systemName: nil)
                        .position(cornerPoint(shape, corner))
                        .gesture(resizeGesture(corner))
                }
                rotateHandle(shape)
                actionBar(shape)
            }
            .frame(width: displaySize.width, height: displaySize.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(moveGesture())          // drag the body to reposition
        }
    }

    // MARK: - Rendering

    @ViewBuilder
    private func shapePreview(_ shape: PendingShape) -> some View {
        let r = displayRect(shape)
        ShapeOutline(kind: shape.kind)
            .fill((shape.style.fillColor ?? .clear))
            .overlay(
                ShapeOutline(kind: shape.kind)
                    .stroke(shape.style.strokeColor,
                            style: StrokeStyle(lineWidth: max(1, shape.style.strokeWidth * scale),
                                               lineCap: .round, lineJoin: .round))
            )
            .frame(width: r.width, height: r.height)
            .scaleEffect(x: shape.flipH ? -1 : 1, y: shape.flipV ? -1 : 1)
            .rotationEffect(.radians(shape.rotation))
            .position(x: r.midX, y: r.midY)
            .allowsHitTesting(false)
    }

    /// Số đo trực tiếp (mm) của đường ghi kích thước.
    private func measurementBadge(_ shape: PendingShape) -> some View {
        let r = shape.normalizedRect
        let c = displayCenter(shape)
        return Text(TechnicalDrawing.lengthLabel(px: hypot(r.width, r.height)))
            .font(.callout.monospacedDigit().weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .position(x: c.x, y: c.y - 28)
            .allowsHitTesting(false)
    }

    private func selectionBox(_ shape: PendingShape) -> some View {
        let r = displayRect(shape)
        return Rectangle()
            .stroke(Theme.primary.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            .frame(width: r.width, height: r.height)
            .rotationEffect(.radians(shape.rotation))
            .position(x: r.midX, y: r.midY)
            .allowsHitTesting(false)
    }

    private func handle(systemName: String?) -> some View {
        Circle()
            .fill(.white)
            .overlay(Circle().stroke(Theme.primary, lineWidth: 2))
            .frame(width: handleSize, height: handleSize)
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }

    private func rotateHandle(_ shape: PendingShape) -> some View {
        let p = rotateHandlePoint(shape)
        return Image(systemName: "arrow.clockwise")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: handleSize, height: handleSize)
            .background(Theme.primary, in: Circle())
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            .position(p)
            .gesture(rotateGesture())
    }

    private func actionBar(_ shape: PendingShape) -> some View {
        HStack(spacing: 14) {
            barButton("arrow.left.and.right.righttriangle.left.righttriangle.right", "Flip H") {
                vm.pendingShape?.flipH.toggle(); Haptics.select()
            }
            barButton("arrow.up.and.down.righttriangle.up.righttriangle.down", "Flip V") {
                vm.pendingShape?.flipV.toggle(); Haptics.select()
            }
            Divider().frame(height: 20)
            barButton("xmark", "Cancel") { vm.cancelPendingShape() }
            barButton("checkmark", "Add", tint: Theme.primary) { vm.commitPendingShape() }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Theme.ink.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        .position(x: displaySize.width / 2, y: displaySize.height - 40)
    }

    private func barButton(_ icon: String, _ label: String, tint: Color = Theme.ink,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    // MARK: - Geometry helpers

    private func displayRect(_ shape: PendingShape) -> CGRect {
        let r = shape.kind.isLinear ? shape.rect.standardized : shape.normalizedRect
        return CGRect(x: r.minX * scale, y: r.minY * scale,
                      width: r.width * scale, height: r.height * scale)
    }

    private func displayCenter(_ shape: PendingShape) -> CGPoint {
        CGPoint(x: shape.center.x * scale, y: shape.center.y * scale)
    }

    private func cornerPoint(_ shape: PendingShape, _ corner: Corner) -> CGPoint {
        let r = displayRect(shape)
        let (sx, sy) = corner.sign
        let local = CGVector(dx: sx * r.width / 2, dy: sy * r.height / 2)
        let rot = rotate(local, by: shape.rotation)
        let c = displayCenter(shape)
        return CGPoint(x: c.x + rot.dx, y: c.y + rot.dy)
    }

    private func rotateHandlePoint(_ shape: PendingShape) -> CGPoint {
        let r = displayRect(shape)
        let local = CGVector(dx: 0, dy: -(r.height / 2 + 34))
        let rot = rotate(local, by: shape.rotation)
        let c = displayCenter(shape)
        return CGPoint(x: c.x + rot.dx, y: c.y + rot.dy)
    }

    private func rotate(_ v: CGVector, by a: CGFloat) -> CGVector {
        CGVector(dx: v.dx * cos(a) - v.dy * sin(a), dy: v.dx * sin(a) + v.dy * cos(a))
    }

    // MARK: - Gestures

    private func moveGesture() -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let start = dragStart ?? vm.pendingShape
                dragStart = start
                guard let start else { return }
                let dx = value.translation.width / scale
                let dy = value.translation.height / scale
                vm.pendingShape?.rect = start.rect.offsetBy(dx: dx, dy: dy)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func rotateGesture() -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard let shape = vm.pendingShape else { return }
                let c = displayCenter(shape)
                let angle = atan2(value.location.y - c.y, value.location.x - c.x) + .pi / 2
                vm.pendingShape?.rotation = angle
            }
    }

    /// Symmetric resize about the shape centre (rotation-safe): the dragged corner
    /// tracks the finger in the shape's own frame, the opposite corner mirrors it.
    private func resizeGesture(_ corner: Corner) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let start = dragStart ?? vm.pendingShape
                dragStart = start
                guard let start else { return }
                let (sx, sy) = corner.sign
                // Drag delta in display → canvas, then into the shape's local frame.
                let deltaCanvas = CGVector(dx: value.translation.width / scale,
                                           dy: value.translation.height / scale)
                let local = rotate(deltaCanvas, by: -start.rotation)
                let base = start.normalizedRect
                var hw = base.width / 2 + sx * local.dx
                var hh = base.height / 2 + sy * local.dy
                hw = max(6, hw); hh = max(6, hh)
                let c = start.center
                vm.pendingShape?.rect = CGRect(x: c.x - hw, y: c.y - hh, width: hw * 2, height: hh * 2)
            }
            .onEnded { _ in dragStart = nil }
    }
}

/// SwiftUI path for a shape kind, used only for the live on-screen preview (the
/// committed artwork is built from PKStrokes by `ShapeFactory`).
struct ShapeOutline: Shape {
    let kind: ShapeKind

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch kind {
        case .rectangle:
            p.addRect(rect)
        case .ellipse:
            p.addEllipse(in: rect)
        case .line, .dimension:
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        default:
            // Polygonal kinds (triangle, diamond, star, pentagon, hexagon,
            // arrow, heart) share their vertex geometry with the baked strokes.
            let verts = ShapeFactory.polygonVertices(kind: kind, rect: rect)
            guard let first = verts.first else { break }
            p.move(to: first)
            for v in verts.dropFirst() { p.addLine(to: v) }
            p.closeSubpath()
        }
        return p
    }
}
