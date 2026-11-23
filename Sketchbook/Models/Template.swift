import SwiftUI

/// Paper / page templates rendered behind the drawing layers.
enum TemplateKind: String, CaseIterable, Codable, Identifiable {
    case blank
    case ringFile      // ring-binder holes + margin + ruled lines
    case ruled
    case grid
    case dotGrid
    case isometric
    case storyboard
    case musicStaff
    case mmGrid        // vẽ kỹ thuật: lưới milimét
    case drawingFrame  // vẽ kỹ thuật: khung bản vẽ + khung tên

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blank: return "Trắng"
        case .ringFile: return "Giấy còng"
        case .ruled: return "Kẻ dòng"
        case .grid: return "Ô vuông"
        case .dotGrid: return "Lưới chấm"
        case .isometric: return "Trục đo"
        case .storyboard: return "Phân cảnh"
        case .musicStaff: return "Khuông nhạc"
        case .mmGrid: return "Lưới mm"
        case .drawingFrame: return "Khung bản vẽ"
        }
    }

    var systemImage: String {
        switch self {
        case .blank: return "rectangle"
        case .ringFile: return "ring.circle"
        case .ruled: return "list.bullet"
        case .grid: return "grid"
        case .dotGrid: return "circle.grid.3x3"
        case .isometric: return "cube"
        case .storyboard: return "rectangle.split.3x3"
        case .musicStaff: return "music.note.list"
        case .mmGrid: return "squareshape.split.3x3"
        case .drawingFrame: return "doc.richtext"
        }
    }
}
