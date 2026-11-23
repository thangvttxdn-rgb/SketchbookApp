import SwiftUI

/// Persisted user preferences. Keys are shared with `NewSketchSheet`,
/// `EditorViewModel`, `Haptics` and the app root.
enum SettingsKey {
    static let defaultTemplate = "defaultTemplate"
    static let defaultLandscape = "defaultLandscape"
    static let defaultBrush = "defaultBrush"
    static let defaultPencilGrade = "defaultPencilGrade"
    static let defaultEraseSize = "defaultEraseSize"
    static let fingerDrawing = "fingerDrawing"   // default: off on iPad (Pencil only), on for iPhone
    static let haptics = "haptics"               // default true
    static let theme = "theme"                   // light | dark | system (default light)
}

enum AppTheme: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }
    var title: String {
        switch self {
        case .light: return "Sáng"
        case .dark: return "Tối"
        case .system: return "Theo hệ thống"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: DocumentStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage(SettingsKey.theme) private var theme = AppTheme.light.rawValue
    // Default OFF on iPad (Pencil draws, fingers pan/zoom/undo); ON on iPhone
    // (no Apple Pencil support). Mirrors EditorViewModel.init.
    @AppStorage(SettingsKey.fingerDrawing) private var fingerDrawing =
        UIDevice.current.userInterfaceIdiom != .pad
    @AppStorage(SettingsKey.haptics) private var haptics = true
    @AppStorage(SettingsKey.defaultTemplate) private var defaultTemplate = TemplateKind.blank.rawValue
    @AppStorage(SettingsKey.defaultLandscape) private var defaultLandscape = true
    @AppStorage(SettingsKey.defaultBrush) private var defaultBrush = BrushType.pen.rawValue
    @AppStorage(SettingsKey.defaultPencilGrade) private var defaultPencilGrade = PencilGrade.hb.rawValue
    @AppStorage(SettingsKey.defaultEraseSize) private var defaultEraseSize = 24.0

    private let developerURL = URL(string: "https://github.com/alfredang/sketchbookapp")!
    private var versionString: String {
        let i = Bundle.main.infoDictionary
        let s = i?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = i?["CFBundleVersion"] as? String ?? "1"
        return "\(s) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Giao diện") {
                    Picker("Chủ đề", selection: $theme) {
                        ForEach(AppTheme.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                }

                Section("Vẽ") {
                    Toggle("Vẽ bằng ngón tay", isOn: $fingerDrawing)
                    HStack {
                        Label("Chống chạm lòng bàn tay", systemImage: "hand.raised.fill")
                        Spacer()
                        Text("Luôn bật").foregroundStyle(Theme.mutedInk)
                    }
                    Toggle("Rung phản hồi", isOn: $haptics)
                }

                Section("Mặc định công cụ") {
                    Picker("Cọ", selection: $defaultBrush) {
                        ForEach(BrushType.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Picker("Độ cứng bút chì", selection: $defaultPencilGrade) {
                        ForEach(PencilGrade.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    VStack(alignment: .leading) {
                        Text("Cỡ tẩy: \(Int(defaultEraseSize)) pt")
                            .font(.caption).foregroundStyle(Theme.mutedInk)
                        Slider(value: $defaultEraseSize, in: 6...80)
                    }
                }

                Section("Mặc định bản vẽ mới") {
                    Picker("Mẫu giấy", selection: $defaultTemplate) {
                        ForEach(TemplateKind.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Toggle("Khổ ngang", isOn: $defaultLandscape)
                }

                Section("Lưu trữ") {
                    HStack {
                        Label(store.usingICloud ? "iCloud" : "Trên máy này",
                              systemImage: store.usingICloud ? "icloud.fill" : "internaldrive")
                        Spacer()
                        Text(store.usingICloud ? "Đã đồng bộ" : "Cục bộ").foregroundStyle(Theme.mutedInk)
                    }
                }

                Section("Giới thiệu") {
                    Link(destination: developerURL) {
                        Label("Mã nguồn gốc (MIT)", systemImage: "globe")
                    }
                    HStack { Text("Phiên bản"); Spacer(); Text(versionString).foregroundStyle(Theme.mutedInk) }
                }
            }
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } }
            }
        }
    }
}
