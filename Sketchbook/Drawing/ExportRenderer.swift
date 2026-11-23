import SwiftUI
import UIKit

/// Xuất sổ vẽ ra file: PDF nhiều trang (đúng khổ giấy) và PNG từng trang.
/// File được ghi vào thư mục tạm rồi chuyển cho bảng Chia sẻ của iPadOS.
enum ExportRenderer {
    /// Kích thước trang PDF (point) tương ứng canvas, theo quy ước 1 mm = `pxPerMM` px.
    /// Khổ A4 1654 × 2339 px → 595 × 842 pt.
    static func pdfPageSize(for canvas: CGSize) -> CGSize {
        let ptPerPx = 72.0 / 25.4 / TechnicalDrawing.pxPerMM
        return CGSize(width: canvas.width * ptPerPx, height: canvas.height * ptPerPx)
    }

    /// Ảnh phẳng của một trang (bỏ lớp tham chiếu, giữ nền + mẫu giấy).
    static func pageImage(_ document: SketchDocument, pageIndex: Int, scale: CGFloat = 1) -> UIImage {
        var doc = document
        doc.currentPageIndex = pageIndex
        return LayerCompositor.composite(doc, includeReference: false, includeBackground: true, scale: scale)
    }

    /// PDF gồm tất cả trang của sổ.
    static func pdf(_ document: SketchDocument) throws -> URL {
        let pageRect = CGRect(origin: .zero, size: pdfPageSize(for: document.canvasSize))
        let meta: [String: Any] = [kCGPDFContextTitle as String: document.title,
                                   kCGPDFContextCreator as String: "Vẽ Tranh"]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = meta
        let url = tempURL(document.title, ext: "pdf")
        try UIGraphicsPDFRenderer(bounds: pageRect, format: format).writePDF(to: url) { ctx in
            for i in document.pages.indices {
                ctx.beginPage()
                // autoreleasepool: giải phóng ảnh từng trang, tránh tràn bộ nhớ với sổ dài.
                autoreleasepool {
                    pageImage(document, pageIndex: i).draw(in: pageRect)
                }
            }
        }
        return url
    }

    /// PNG của các trang được chọn (mặc định: tất cả).
    static func pngs(_ document: SketchDocument, pages: [Int]? = nil) throws -> [URL] {
        let indices = pages ?? Array(document.pages.indices)
        return try indices.map { (i: Int) -> URL in
            let suffix = document.pages.count > 1 ? " - trang \(i + 1)" : ""
            let url = tempURL(document.title + suffix, ext: "png")
            let data = autoreleasepool { pageImage(document, pageIndex: i).pngData() }
            try (data ?? Data()).write(to: url, options: .atomic)
            return url
        }
    }

    private static func tempURL(_ name: String, ext: String) -> URL {
        let safe = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(safe.isEmpty ? "Ve-tranh" : safe).appendingPathExtension(ext)
    }
}

/// Bảng Chia sẻ (AirDrop, Tệp, Mail, Zalo…) cho các file đã xuất.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Gói danh sách file để dùng với `.sheet(item:)`.
struct ExportedFiles: Identifiable {
    let id = UUID()
    let urls: [URL]
}
