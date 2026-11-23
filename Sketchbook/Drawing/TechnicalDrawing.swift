import UIKit

/// Vẽ kỹ thuật: quy đổi mm ↔ pixel, lưới mm, khung bản vẽ + khung tên và nhãn
/// ghi kích thước.
///
/// Quy ước: khổ A4/A3 được tạo ở 200 dpi (A4 = 1654 px ngang = 210 mm), nên
/// 1 mm = 1654 / 210 ≈ 7,876 px. Mọi canvas dùng cùng hệ số này, vì vậy số đo
/// trên khổ A4/A3 khớp tỉ lệ 1:1 khi in.
enum TechnicalDrawing {
    static let pxPerMM: CGFloat = 1654.0 / 210.0

    static func mm(_ px: CGFloat) -> CGFloat { px / pxPerMM }

    /// Chuỗi số đo, ví dụ "125 mm" hoặc "12,5 mm".
    static func lengthLabel(px: CGFloat) -> String {
        let value = mm(px)
        let f = NumberFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.maximumFractionDigits = value < 100 ? 1 : 0
        f.minimumFractionDigits = 0
        return (f.string(from: NSNumber(value: Double(value))) ?? "\(Int(value))") + " mm"
    }

    // MARK: - Mẫu giấy

    /// Lưới mm: nét 1 mm rất nhạt, 5 mm nhạt, 10 mm đậm hơn.
    static func drawMMGrid(_ c: CGContext, size: CGSize) {
        let levels: [(step: Int, alpha: CGFloat, width: CGFloat)] = [(1, 0.05, 1), (5, 0.10, 1), (10, 0.20, 1.5)]
        for level in levels {
            UIColor(red: 0.1, green: 0.35, blue: 0.6, alpha: level.alpha).setStroke()
            c.setLineWidth(level.width)
            var i = 0
            while CGFloat(i) * pxPerMM <= size.width {
                if i % level.step == 0 {
                    let x = CGFloat(i) * pxPerMM
                    c.move(to: CGPoint(x: x, y: 0)); c.addLine(to: CGPoint(x: x, y: size.height))
                }
                i += 1
            }
            i = 0
            while CGFloat(i) * pxPerMM <= size.height {
                if i % level.step == 0 {
                    let y = CGFloat(i) * pxPerMM
                    c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: size.width, y: y))
                }
                i += 1
            }
            c.strokePath()
        }
    }

    /// Khung bản vẽ: lề trái 20 mm (đóng tập), các lề còn lại 5 mm, kèm khung
    /// tên 140 × 32 mm ở góc phải dưới.
    static func drawFrame(_ c: CGContext, size: CGSize) {
        let k = pxPerMM
        let frame = CGRect(x: 20 * k, y: 5 * k,
                           width: size.width - 25 * k, height: size.height - 10 * k)
        guard frame.width > 150 * k, frame.height > 40 * k else {
            // Canvas quá nhỏ cho khung tên: chỉ vẽ viền.
            UIColor.black.setStroke(); c.setLineWidth(0.7 * k); c.stroke(frame)
            return
        }
        UIColor.black.setStroke()
        c.setLineWidth(0.7 * k)
        c.stroke(frame)

        // Khung tên.
        let tb = CGRect(x: frame.maxX - 140 * k, y: frame.maxY - 32 * k, width: 140 * k, height: 32 * k)
        c.stroke(tb)
        c.setLineWidth(0.35 * k)
        let col1 = tb.minX + 25 * k, col2 = tb.minX + 55 * k, col3 = tb.minX + 110 * k
        for x in [col1, col2, col3] {
            c.move(to: CGPoint(x: x, y: tb.minY)); c.addLine(to: CGPoint(x: x, y: tb.maxY))
        }
        for i in 1..<4 {
            let y = tb.minY + CGFloat(i) * 8 * k
            c.move(to: CGPoint(x: tb.minX, y: y)); c.addLine(to: CGPoint(x: col2, y: y))
            c.move(to: CGPoint(x: col3, y: y)); c.addLine(to: CGPoint(x: tb.maxX, y: y))
        }
        c.strokePath()

        let font = UIFont.systemFont(ofSize: 3 * k)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.darkGray]
        let leftRows = ["Người vẽ", "Kiểm tra", "Duyệt", "Ngày"]
        for (i, text) in leftRows.enumerated() {
            (text as NSString).draw(at: CGPoint(x: tb.minX + 1.5 * k, y: tb.minY + CGFloat(i) * 8 * k + 2 * k),
                                    withAttributes: attrs)
        }
        let rightRows = ["Tỉ lệ", "Vật liệu", "Số BV", "Tờ"]
        for (i, text) in rightRows.enumerated() {
            (text as NSString).draw(at: CGPoint(x: col3 + 1.5 * k, y: tb.minY + CGFloat(i) * 8 * k + 2 * k),
                                    withAttributes: attrs)
        }
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 3.5 * k),
                                                         .foregroundColor: UIColor.darkGray]
        ("TÊN BẢN VẼ" as NSString).draw(at: CGPoint(x: col2 + 2 * k, y: tb.minY + 3 * k), withAttributes: titleAttrs)
        ("Chi nhánh Toa xe Đà Nẵng" as NSString).draw(at: CGPoint(x: col2 + 2 * k, y: tb.maxY - 7 * k),
                                                     withAttributes: attrs)
    }

    // MARK: - Nhãn ghi kích thước

    /// Ảnh trong suốt cỡ canvas chứa nhãn số đo đặt giữa đoạn `a`–`b`, xoay theo
    /// hướng đoạn thẳng (luôn đọc được từ dưới lên/trái sang).
    static func dimensionLabel(from a: CGPoint, to b: CGPoint, color: UIColor,
                               lineWidth: CGFloat, canvasSize: CGSize) -> UIImage {
        let length = hypot(b.x - a.x, b.y - a.y)
        let text = lengthLabel(px: length) as NSString
        let fontSize = max(28, lineWidth * 5)
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
                                                    .foregroundColor: color]
        var angle = atan2(b.y - a.y, b.x - a.x)
        if angle > .pi / 2 { angle -= .pi } else if angle < -.pi / 2 { angle += .pi }
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let textSize = text.size(withAttributes: attrs)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: mid.x, y: mid.y)
            c.rotate(by: angle)
            // Đặt chữ phía trên đường kích thước.
            text.draw(at: CGPoint(x: -textSize.width / 2, y: -textSize.height - lineWidth - 6), withAttributes: attrs)
        }
    }
}
