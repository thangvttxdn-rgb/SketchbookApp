import UIKit

/// Tranh tô màu cho bé — nét vẽ tự sinh bằng code (không dùng hình có bản quyền).
/// Sổ tạo ra có lớp "Nét vẽ" (khoá) nằm TRÊN lớp "Màu tô", nên đổ màu không
/// bao giờ che mất nét.
enum ColoringPage: String, CaseIterable, Identifiable {
    case train, house, flower, fish, sunny, butterfly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .train: return "Tàu hoả"
        case .house: return "Ngôi nhà"
        case .flower: return "Bông hoa"
        case .fish: return "Con cá"
        case .sunny: return "Trời nắng"
        case .butterfly: return "Con bướm"
        }
    }

    static let canvasSize = CGSize(width: 2048, height: 1536)

    /// Ảnh nét vẽ trong suốt ở kích thước `size`.
    func lineArt(size: CGSize = ColoringPage.canvasSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let c = ctx.cgContext
            // Vẽ trong hệ toạ độ chuẩn 2048 × 1536 rồi co theo `size`.
            c.scaleBy(x: size.width / Self.canvasSize.width, y: size.height / Self.canvasSize.height)
            UIColor.black.setStroke()
            draw(Pen())
        }
    }

    func makeDocument() -> SketchDocument {
        var doc = SketchDocument(title: title, template: .blank, size: Self.canvasSize)
        let colors = Layer(name: "Màu tô")
        let lines = Layer(name: "Nét vẽ", isLocked: true, imageData: lineArt().pngData())
        doc.pages = [Page(layers: [colors, lines], activeLayerIndex: 0)]
        doc.currentPageIndex = 0
        doc.thumbnailData = LayerCompositor.thumbnail(doc).pngData()
        return doc
    }

    // MARK: - Nét vẽ

    private func draw(_ p: Pen) {
        switch self {
        case .train:
            p.line(0, 1330, 2048, 1330)                       // ray
            p.line(0, 1380, 2048, 1380)
            for x in stride(from: 40.0, to: 2048, by: 120) { p.rect(x, 1330, 60, 50) } // tà vẹt
            p.rect(1100, 800, 600, 380)                       // thân đầu máy
            p.rect(1500, 560, 200, 240)                       // ca-bin
            p.rect(1540, 600, 120, 110)                       // cửa sổ ca-bin
            p.rect(1180, 640, 90, 160)                        // ống khói
            p.path { b in                                      // mũi gạt đá
                b.move(to: CGPoint(x: 1100, y: 1080)); b.addLine(to: CGPoint(x: 1010, y: 1180))
                b.addLine(to: CGPoint(x: 1100, y: 1180)); b.close()
            }
            p.rect(250, 820, 760, 360)                         // toa xe
            for x in [300.0, 540, 780] { p.rect(x, 870, 180, 140) } // cửa sổ toa
            p.line(1010, 1120, 1100, 1120)                     // móc nối
            for x in [380.0, 880, 1220, 1420, 1600] { p.circle(x, 1250, 75); p.circle(x, 1250, 22) } // bánh xe
            p.cloud(1010, 470, 90)                             // khói
            p.cloud(820, 330, 70)
            p.circle(300, 250, 110)                            // mặt trời
        case .house:
            p.line(0, 1350, 2048, 1350)
            p.rect(520, 760, 700, 590)                         // tường
            p.path { b in                                      // mái
                b.move(to: CGPoint(x: 440, y: 780)); b.addLine(to: CGPoint(x: 870, y: 380))
                b.addLine(to: CGPoint(x: 1300, y: 780)); b.close()
            }
            p.rect(800, 1030, 160, 320)                        // cửa
            p.circle(930, 1190, 12)
            for x in [600.0, 1020] {                           // cửa sổ có song
                p.rect(x, 860, 140, 140)
                p.line(x + 70, 860, x + 70, 1000); p.line(x, 930, x + 140, 930)
            }
            p.rect(1530, 1050, 80, 300)                        // thân cây
            p.circle(1570, 900, 210)                           // tán cây
            p.circle(1750, 220, 110)                           // mặt trời
            p.cloud(300, 260, 80)
        case .flower:
            p.path { b in                                      // chậu
                b.move(to: CGPoint(x: 820, y: 1150)); b.addLine(to: CGPoint(x: 1228, y: 1150))
                b.addLine(to: CGPoint(x: 1160, y: 1460)); b.addLine(to: CGPoint(x: 888, y: 1460)); b.close()
            }
            p.rect(1004, 640, 40, 510)                         // thân
            p.ellipse(1024 - 250, 900, 230, 110, angle: -0.5)  // lá
            p.ellipse(1024 + 20, 980, 230, 110, angle: 0.5)
            for i in 0..<8 {                                   // cánh hoa
                let a = Double(i) * .pi / 4
                let cx = 1024 + cos(a) * 210, cy = 480 + sin(a) * 210
                p.ellipse(cx - 120, cy - 70, 240, 140, angle: CGFloat(a))
            }
            p.circle(1024, 480, 120)                           // nhuỵ
        case .fish:
            p.ellipse(560, 480, 900, 560)                      // thân
            p.path { b in                                      // đuôi
                b.move(to: CGPoint(x: 1440, y: 760)); b.addLine(to: CGPoint(x: 1780, y: 520))
                b.addLine(to: CGPoint(x: 1780, y: 1000)); b.close()
            }
            p.path { b in                                      // vây lưng
                b.move(to: CGPoint(x: 900, y: 500)); b.addLine(to: CGPoint(x: 1060, y: 330))
                b.addLine(to: CGPoint(x: 1200, y: 510))
            }
            p.circle(760, 680, 55); p.circle(760, 680, 20)     // mắt
            p.arc(1000, 760, 180, from: -0.9, to: 0.9)         // mang/vảy
            p.arc(1150, 760, 180, from: -0.9, to: 0.9)
            for (x, y, r) in [(360.0, 520.0, 40.0), (300, 380, 30), (380, 260, 22)] { p.circle(x, y, r) }
            p.wave(y: 1250); p.wave(y: 1380)
        case .sunny:
            p.circle(1024, 600, 230)                           // mặt trời
            for i in 0..<12 {                                  // tia nắng
                let a = Double(i) * .pi / 6
                let r1 = 270.0, r2 = 400.0, w = 0.13
                p.path { b in
                    b.move(to: CGPoint(x: 1024 + cos(a - w) * r1, y: 600 + sin(a - w) * r1))
                    b.addLine(to: CGPoint(x: 1024 + cos(a) * r2, y: 600 + sin(a) * r2))
                    b.addLine(to: CGPoint(x: 1024 + cos(a + w) * r1, y: 600 + sin(a + w) * r1)); b.close()
                }
            }
            p.circle(950, 560, 25); p.circle(1100, 560, 25)    // mắt
            p.arc(1024, 640, 100, from: 0.3, to: .pi - 0.3)    // miệng cười
            p.cloud(330, 330, 100)
            p.cloud(1700, 380, 90)
            p.arc(500, 1700, 700, from: -.pi, to: 0)           // đồi
            p.arc(1600, 1750, 750, from: -.pi, to: 0)
        case .butterfly:
            p.ellipse(560, 300, 440, 520, angle: -0.3)         // cánh trên
            p.ellipse(1048, 300, 440, 520, angle: 0.3)
            p.ellipse(640, 760, 360, 400, angle: 0.3)          // cánh dưới
            p.ellipse(1048, 760, 360, 400, angle: -0.3)
            p.ellipse(984, 400, 128, 820)                      // thân
            p.circle(1048, 340, 70)                            // đầu
            p.line(1020, 290, 900, 130); p.circle(890, 115, 25) // râu
            p.line(1076, 290, 1196, 130); p.circle(1206, 115, 25)
            for (x, y, r) in [(760.0, 540.0, 70.0), (1336, 540, 70), (800, 950, 55), (1296, 950, 55)] { p.circle(x, y, r) }
        }
    }
}

/// Bút vẽ nét đen dày, đầu tròn, cho tranh tô màu.
private struct Pen {
    let width: CGFloat = 12

    private func stroke(_ b: UIBezierPath) {
        b.lineWidth = width
        b.lineJoinStyle = .round
        b.lineCapStyle = .round
        b.stroke()
    }

    func path(_ build: (UIBezierPath) -> Void) { let b = UIBezierPath(); build(b); stroke(b) }

    func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
        path { b in b.move(to: CGPoint(x: x1, y: y1)); b.addLine(to: CGPoint(x: x2, y: y2)) }
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        stroke(UIBezierPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: 8))
    }

    func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
        stroke(UIBezierPath(ovalIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)))
    }

    /// Hình elip trong khung (x, y, w, h), xoay `angle` rad quanh tâm.
    func ellipse(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, angle: CGFloat = 0) {
        let b = UIBezierPath(ovalIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        b.apply(CGAffineTransform(rotationAngle: angle))
        b.apply(CGAffineTransform(translationX: x + w / 2, y: y + h / 2))
        stroke(b)
    }

    func arc(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, from a: CGFloat, to b: CGFloat) {
        stroke(UIBezierPath(arcCenter: CGPoint(x: cx, y: cy), radius: r, startAngle: a, endAngle: b, clockwise: true))
    }

    /// Đám mây: thân bo tròn + hai vòng tròn phía trên (các vùng nhỏ bên trong
    /// cũng tô được).
    func cloud(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
        stroke(UIBezierPath(roundedRect: CGRect(x: cx - 2 * r, y: cy, width: 4 * r, height: r * 1.2),
                            cornerRadius: r * 0.6))
        circle(cx - 0.8 * r, cy, r * 0.8)
        circle(cx + 0.5 * r, cy - 0.2 * r, r)
    }

    /// Sóng nước ngang toàn khổ.
    func wave(y: CGFloat) {
        path { b in
            b.move(to: CGPoint(x: 0, y: y))
            var x: CGFloat = 0
            while x < 2048 {
                b.addQuadCurve(to: CGPoint(x: x + 128, y: y), controlPoint: CGPoint(x: x + 64, y: y - 40))
                x += 128
            }
        }
    }
}
