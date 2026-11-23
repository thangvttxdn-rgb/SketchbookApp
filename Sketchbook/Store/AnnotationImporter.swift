import PDFKit
import UIKit

/// Tạo sổ vẽ để ghi chú lên ảnh chụp hoặc file PDF. Mỗi trang có:
/// lớp dưới "Nền" (ảnh/PDF, khoá, không sửa được) và lớp trên "Ghi chú" để vẽ.
/// Xuất PDF lại sẽ ra bản đã chú thích.
enum AnnotationImporter {
    /// Giới hạn số trang PDF nhập vào (mỗi trang lưu một ảnh PNG trong sổ).
    static let maxPDFPages = 30
    /// Cạnh dài tối đa của ảnh nền (px) — tương đương A3 ở 200 dpi.
    static let maxSide: CGFloat = 3308

    enum ImportError: LocalizedError {
        case unreadablePDF, emptyPDF
        var errorDescription: String? {
            switch self {
            case .unreadablePDF: return "Không đọc được file PDF (có thể bị khoá mật khẩu)."
            case .emptyPDF: return "File PDF không có trang nào."
            }
        }
    }

    static func document(fromImage image: UIImage, title: String) -> SketchDocument {
        let bg = normalized(image)
        var doc = SketchDocument(title: title, template: .blank, size: bg.size)
        doc.pages = [page(background: bg)]
        doc.currentPageIndex = 0
        doc.thumbnailData = LayerCompositor.thumbnail(doc).pngData()
        return doc
    }

    /// Trả về sổ vẽ và số trang PDF bị bỏ qua do vượt giới hạn.
    static func document(fromPDF url: URL) throws -> (SketchDocument, skippedPages: Int) {
        guard let pdf = PDFDocument(url: url), !pdf.isLocked else { throw ImportError.unreadablePDF }
        guard pdf.pageCount > 0, let first = pdf.page(at: 0) else { throw ImportError.emptyPDF }

        // Kích thước canvas theo trang đầu, quy đổi point → px theo 1 mm = pxPerMM.
        let pxPerPt = TechnicalDrawing.pxPerMM * 25.4 / 72
        var canvas = displaySize(first)
        canvas = CGSize(width: canvas.width * pxPerPt, height: canvas.height * pxPerPt)
        let shrink = min(maxSide / max(canvas.width, canvas.height), 1)
        canvas = CGSize(width: (canvas.width * shrink).rounded(), height: (canvas.height * shrink).rounded())

        let title = url.deletingPathExtension().lastPathComponent
        var doc = SketchDocument(title: title, template: .blank, size: canvas)
        let count = min(pdf.pageCount, maxPDFPages)
        doc.pages = (0..<count).compactMap { (i: Int) -> Page? in
            guard let p = pdf.page(at: i) else { return nil }
            return autoreleasepool { page(background: render(p, into: canvas)) }
        }
        doc.currentPageIndex = 0
        doc.thumbnailData = LayerCompositor.thumbnail(doc).pngData()
        return (doc, pdf.pageCount - count)
    }

    // MARK: - Helpers

    private static func page(background: UIImage) -> Page {
        let bg = Layer(name: "Nền", isLocked: true, imageData: background.pngData())
        let notes = Layer(name: "Ghi chú")
        return Page(layers: [bg, notes], activeLayerIndex: 1)
    }

    /// Vẽ trang PDF lên nền trắng, căn giữa, giữ tỉ lệ (thumbnail của PDFKit đã
    /// xử lý chiều xoay trang và gốc toạ độ).
    private static func render(_ page: PDFPage, into size: CGSize) -> UIImage {
        let thumb = page.thumbnail(of: size, for: .mediaBox)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fill(CGRect(origin: .zero, size: size))
            let t = CGSize(width: thumb.size.width * thumb.scale, height: thumb.size.height * thumb.scale)
            let s = min(size.width / max(t.width, 1), size.height / max(t.height, 1))
            let fit = CGSize(width: t.width * s, height: t.height * s)
            thumb.draw(in: CGRect(x: (size.width - fit.width) / 2, y: (size.height - fit.height) / 2,
                                  width: fit.width, height: fit.height))
        }
    }

    /// Kích thước trang (point) đã tính chiều xoay 90°/270°.
    private static func displaySize(_ page: PDFPage) -> CGSize {
        let b = page.bounds(for: .mediaBox).size
        return page.rotation % 180 == 0 ? b : CGSize(width: b.height, height: b.width)
    }

    /// Ảnh xoay đúng chiều, thu nhỏ nếu quá lớn, scale = 1 (1 điểm = 1 px canvas).
    private static func normalized(_ image: UIImage) -> UIImage {
        let px = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let shrink = min(maxSide / max(px.width, px.height), 1)
        let target = CGSize(width: (px.width * shrink).rounded(), height: (px.height * shrink).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
