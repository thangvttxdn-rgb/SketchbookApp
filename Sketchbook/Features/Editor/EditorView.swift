import SwiftUI
import PencilKit
import PhotosUI
import UniformTypeIdentifiers

struct EditorView: View {
    @EnvironmentObject private var store: DocumentStore
    @StateObject private var vm: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showLayers = false
    @State private var showBrushes = false
    @State private var showShapes = false
    @State private var showWidth = false
    @State private var showFillColor = false
    /// In-progress shape drag (canvas coords) before handles appear.
    @State private var draftRect: CGRect?
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    /// Whether a picked photo becomes artwork content or a tracing reference.
    private enum PhotoTarget { case insert, reference }
    @State private var photoTarget: PhotoTarget = .reference
    @State private var showFileImporter = false
    @State private var showAdjustments = false
    @State private var arImage: UIImage?
    @State private var exported: ExportedFiles?
    @State private var exportError: String?
    @StateObject private var canvasHandle = CanvasHandle()
    @ObservedObject private var orientation = OrientationManager.shared
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.scenePhase) private var scenePhase

    // Live canvas viewport (pinch zoom + pan), reported by the PKCanvasView so
    // every other layer/template image renders in register with the ink.
    // 0 = not yet reported → fit scale, zero offset.
    @State private var canvasZoom: CGFloat = 0
    @State private var canvasOffset: CGPoint = .zero

    // iPad side panel state — both panels start collapsed; the user expands
    // and collapses them manually via the edge affordances.
    @State private var sidePanelTab: SidePanelTab = .brush
    @State private var sidePanelCollapsed = true
    @State private var pagesPanelCollapsed = true

    // Confirmation for destructive "all pages" actions.
    private enum PageConfirm { case clearAll, deleteAll }
    @State private var confirm: PageConfirm?

    /// True on iPad / regular width, where the docked side panel is shown.
    private var isRegular: Bool { hSize == .regular }

    init(document: SketchDocument) {
        _vm = StateObject(wrappedValue: EditorViewModel(document: document))
    }

    var body: some View {
        HStack(spacing: 0) {
            // iPad: docked, collapsible pages sidebar on the left.
            if isRegular {
                if pagesPanelCollapsed {
                    expandPagesButton
                } else {
                    PagesSidebar(vm: vm) {
                        withAnimation(.easeInOut(duration: 0.22)) { pagesPanelCollapsed = true }
                    }
                    .transition(.move(edge: .leading))
                }
            }
            VStack(spacing: 0) {
                topBar
                Divider()
                canvasArea
                    .background(Theme.background)
                    .overlay(alignment: .bottom) { pageControl }
            }
            // iPad: docked, collapsible, tabbed inspector on the right.
            if isRegular {
                if sidePanelCollapsed {
                    expandPanelButton
                } else {
                    EditorSidePanel(vm: vm, tab: $sidePanelTab) {
                        withAnimation(.easeInOut(duration: 0.22)) { sidePanelCollapsed = true }
                    }
                    .transition(.move(edge: .trailing))
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            vm.attach(store: store)
            // Default to a landscape-locked canvas on iPad; unlock or re-lock
            // any time via ••• → Orientation. (Disabled under UI tests, where
            // a forced rotation desyncs XCUITest's coordinate space.)
            let uiTestNoLock = ProcessInfo.processInfo.environment["UITEST_DISABLE_ORIENTATION_LOCK"] != nil
            if isRegular && !orientation.isLocked && !uiTestNoLock {
                orientation.lock(to: .landscape)
            }
        }
        .onDisappear { vm.save(); orientation.unlock() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive { vm.save() }
        }
        .sheet(isPresented: $showLayers) {
            LayersPanel(vm: vm).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showBrushes) {
            BrushPanel(vm: vm).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showShapes) {
            ShapesPanel(vm: vm).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAdjustments) {
            AdjustmentsPanel(vm: vm).presentationDetents([.medium, .large])
        }
        .onChange(of: vm.toolMode) { _, mode in
            // Shape/fill/stardust placement maps taps at the fit scale; snap zoom
            // so the overlay registers with the canvas content.
            if mode == .shape || mode == .fill { canvasHandle.resetZoom() }
        }
        .onChange(of: vm.brush) { _, brush in
            if brush == .stardust { canvasHandle.resetZoom() }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            let target = photoTarget
            photoItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    switch target {
                    case .insert: vm.insertImage(image)
                    case .reference: vm.importReference(image)
                    }
                }
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                vm.insertImage(image)
            }
        }
        .sheet(item: $exported) { files in
            ShareSheet(items: files.urls)
        }
        .alert("Không xuất được file", isPresented: Binding(get: { exportError != nil },
                                                           set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .fullScreenCover(item: Binding(get: { arImage.map { ARImageBox(image: $0) } },
                                       set: { arImage = $0?.image })) { box in
            ARSketchScreen(image: box.image)
        }
    }

    /// Thin affordance shown on the left edge when the pages sidebar is collapsed.
    private var expandPagesButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { pagesPanelCollapsed = false }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.title3)
                .foregroundStyle(Theme.ink)
                .frame(width: 44)
                .frame(maxHeight: .infinity)
                .background(Theme.surface)
        }
        .help("Hiện trang")
        .accessibilityLabel("Show pages")
        .overlay(Divider(), alignment: .trailing)
    }

    /// Thin affordance shown on the right edge when the iPad panel is collapsed.
    private var expandPanelButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { sidePanelCollapsed = false }
        } label: {
            Image(systemName: "sidebar.right")
                .font(.title3)
                .foregroundStyle(Theme.ink)
                .frame(width: 44)
                .frame(maxHeight: .infinity)
                .background(Theme.surface)
        }
        .help("Hiện bảng công cụ")
        .accessibilityLabel("Show panel")
        .overlay(Divider(), alignment: .leading)
    }

    /// Bottom page navigator: flip between pages, add, or delete. Mirrors the
    /// pull gesture (drag firmly past the bottom edge = next/new page, past
    /// the top edge = previous page).
    private var pageControl: some View {
        HStack(spacing: 14) {
            Button { vm.previousPage() } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(vm.currentPage == 0)
            .accessibilityIdentifier("prevPage")
            .accessibilityLabel("Previous page")

            Text("Trang \(vm.currentPage + 1) / \(vm.pageCount)")
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 92)
                .accessibilityIdentifier("pageIndicator")

            Button { vm.nextPage() } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(vm.currentPage == vm.pageCount - 1)
            .accessibilityIdentifier("nextPage")
            .accessibilityLabel("Next page")

            Divider().frame(height: 18)
            pagesMenu
        }
        .font(.title3)
        .tint(Theme.primary)
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Theme.ink.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .padding(.bottom, 14)
    }

    /// Page management: add before/after, clear, delete. Destructive actions
    /// for "all" are confirmed before running.
    private var pagesMenu: some View {
        Menu {
            Button { vm.addPageBefore() } label: { Label("Thêm trang phía trước", systemImage: "arrow.up.to.line") }
            Button { vm.addPageAfter() } label: { Label("Thêm trang phía sau", systemImage: "arrow.down.to.line") }
            Divider()
            Button { vm.clearCurrentPage() } label: { Label("Xoá nét trang này", systemImage: "eraser") }
            Button { confirm = .clearAll } label: { Label("Xoá nét tất cả trang", systemImage: "eraser.line.dashed") }
            Divider()
            Button(role: .destructive) { vm.deleteCurrentPage() } label: {
                Label("Xoá trang này", systemImage: "trash")
            }
            Button(role: .destructive) { confirm = .deleteAll } label: {
                Label("Xoá tất cả trang", systemImage: "trash.slash")
            }
        } label: {
            Image(systemName: "square.stack.3d.up")
        }
        .accessibilityIdentifier("pagesMenu")
        .accessibilityLabel("Pages")
        .confirmationDialog("Thao tác này ảnh hưởng mọi trang trong sổ.",
                            isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible) {
            switch confirm {
            case .clearAll:
                Button("Xoá nét tất cả trang", role: .destructive) { vm.clearAllPages() }
            case .deleteAll:
                Button("Xoá tất cả trang", role: .destructive) { vm.deleteAllPages() }
            case nil:
                EmptyView()
            }
            Button("Huỷ", role: .cancel) {}
        }
    }

    /// Route a picker to the iPad side panel (auto-expanding it) instead of a
    /// pop-up sheet, so the selection UI never covers the canvas / sits too
    /// low. On iPhone (compact width, no side panel) fall back to a sheet.
    private func openPicker(_ tab: SidePanelTab, sheet: () -> Void) {
        if isRegular {
            sidePanelTab = tab
            if sidePanelCollapsed {
                withAnimation(.easeInOut(duration: 0.22)) { sidePanelCollapsed = false }
            }
        } else {
            sheet()
        }
    }

    // MARK: - Top toolbar

    private var topBar: some View {
        HStack(spacing: 6) {
            // Leading — pinned. Always reachable, never clipped.
            iconButton("chevron.left", label: "Back") {
                vm.commitPendingShape()   // don't drop a shape mid-adjustment
                vm.save()
                dismiss()
            }

            Divider().frame(height: 28)

            // Primary tools live in a horizontally scrollable strip so the bar
            // can never overflow / clip controls on narrow iPhone screens.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    brushButton
                    eraserButton

                    ColorPicker("", selection: $vm.color, supportsOpacity: true)
                        .labelsHidden()
                        .frame(width: 32, height: 32)
                        .frame(minWidth: 44, minHeight: 44)

                    iconButton("lineweight", label: "Brush size") { showWidth.toggle() }
                        .popover(isPresented: $showWidth) { widthPopover }

                    shapesButton
                    fillButton
                    toolButton(.lasso)
                    iconButton("wand.and.stars", label: "Adjustments") {
                        openPicker(.adjust) { showAdjustments = true }
                    }
                    gridMenuButton
                    transformMenuButton
                    fingerDrawingButton
                }
                .padding(.horizontal, 2)
            }

            Divider().frame(height: 28)

            // Trailing — pinned. Undo/redo + layers + overflow stay reachable.
            iconButton("arrow.uturn.backward", label: "Undo") { vm.undo() }
                .disabled(!vm.canUndo)
            iconButton("arrow.uturn.forward", label: "Redo") { vm.redo() }
                .disabled(!vm.canRedo)
            iconButton("square.3.layers.3d", label: "Layers") {
                openPicker(.layers) { showLayers = true }
            }
            overflowMenu
        }
        .font(.title3)
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Theme.surface)
    }

    /// A toolbar icon button with a HIG-compliant 44×44 pt tap target.
    private func iconButton(_ systemName: String, label: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .help(label)
        .accessibilityLabel(label)
    }

    // Brush (draw) — shows the current brush and opens the brush picker.
    private var brushButton: some View {
        Button {
            vm.toolMode = .draw
            openPicker(.brush) { showBrushes = true }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: vm.brush.systemImage)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .foregroundStyle(vm.toolMode == .draw ? .white : Theme.ink)
            .padding(.horizontal, 10).frame(minWidth: 44, minHeight: 44)
            .background(vm.toolMode == .draw ? Theme.primary : .clear,
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .help("Cọ vẽ")
        .accessibilityLabel("Brushes")
    }

    // Eraser — tap to select; tap again (when active) to adjust size.
    private var eraserButton: some View {
        Button {
            if vm.toolMode == .erase { showWidth = true } else { vm.toolMode = .erase; Haptics.select() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "eraser")
                if vm.toolMode == .erase { Image(systemName: "chevron.down").font(.caption2) }
            }
            .foregroundStyle(vm.toolMode == .erase ? .white : Theme.ink)
            .padding(.horizontal, 10).frame(minWidth: 44, minHeight: 44)
            .background(vm.toolMode == .erase ? Theme.primary : .clear,
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .help("Tẩy")
        .accessibilityLabel("Eraser")
    }

    // Shapes — selects shape mode and opens the shape picker.
    private var shapesButton: some View {
        Button {
            vm.toolMode = .shape
            openPicker(.shapes) { showShapes = true }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: vm.shapeKind.systemImage)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .foregroundStyle(vm.toolMode == .shape ? .white : Theme.ink)
            .padding(.horizontal, 10).frame(minWidth: 44, minHeight: 44)
            .background(vm.toolMode == .shape ? Theme.primary : .clear,
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .help("Hình")
        .accessibilityLabel("Shapes")
    }

    /// Grid / template picker, promoted from the overflow menu to the top bar.
    private var gridMenuButton: some View {
        Menu {
            ForEach(TemplateKind.allCases) { kind in
                Button { vm.setTemplate(kind) } label: {
                    Label(kind.title, systemImage: vm.document.template == kind ? "checkmark" : kind.systemImage)
                }
            }
        } label: {
            Image(systemName: "grid")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .help("Lưới & mẫu giấy")
        .accessibilityLabel("Grid")
    }

    /// Flip / fit transform menu, promoted from the overflow menu to the top bar.
    private var transformMenuButton: some View {
        Menu {
            Button { vm.flipHorizontal() } label: {
                Label("Lật ngang", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            Button { vm.flipVertical() } label: {
                Label("Lật dọc", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down")
            }
            Button { canvasHandle.resetZoom() } label: {
                Label("Vừa khung", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
            }
        } label: {
            Image(systemName: "crop.rotate")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .help("Biến đổi")
        .accessibilityLabel("Transform")
    }

    /// Fill tool — tap to select; tap again (when active) for the colour
    /// dialog. Opening the dialog on the FIRST tap would swallow the next
    /// canvas tap as a popover dismissal, forcing an extra tap before every
    /// fill (mirrors the eraser button's tap-again-for-size pattern).
    private var fillButton: some View {
        Button {
            if vm.toolMode == .fill { showFillColor = true }
            else { vm.toolMode = .fill; Haptics.select() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: ToolMode.fill.systemImage)
                if vm.toolMode == .fill { Image(systemName: "chevron.down").font(.caption2) }
            }
            .foregroundStyle(vm.toolMode == .fill ? .white : Theme.ink)
            .padding(.horizontal, 10).frame(minWidth: 44, minHeight: 44)
            .background(vm.toolMode == .fill ? Theme.primary : .clear,
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .help("Đổ màu")
        .accessibilityLabel("Fill")
        .popover(isPresented: $showFillColor) { fillColorPopover }
    }

    /// Compact fill-colour dialog: system colour well + quick swatches.
    private var fillColorPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            ColorPicker("Fill Color", selection: $vm.color, supportsOpacity: true)
                .font(.subheadline.weight(.semibold))
            let swatches = ["#111418", "#FFFFFF", "#E53935", "#FB8C00",
                            "#FDD835", "#43A047", "#1E88E5", "#8E24AA"]
            HStack(spacing: 8) {
                ForEach(swatches, id: \.self) { hex in
                    let c = Color(hex: hex)
                    Button { vm.color = c } label: {
                        Circle().fill(c)
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Theme.mutedInk.opacity(0.3), lineWidth: 1))
                    }
                }
            }
            Text("Chạm vào hình hoặc vùng kín để đổ màu.")
                .font(.caption).foregroundStyle(Theme.mutedInk)
        }
        .padding(14).frame(width: 300)
        .presentationCompactAdaptation(.popover)
    }

    /// Finger drawing on/off, visible in the bar (not buried in the overflow
    /// menu): with the iPad default being Pencil-only, users without an Apple
    /// Pencil need one obvious tap to start drawing with a finger.
    private var fingerDrawingButton: some View {
        Button { vm.setFingerDrawing(!vm.fingerDrawingEnabled) } label: {
            Image(systemName: vm.fingerDrawingEnabled ? "hand.draw.fill" : "hand.draw")
                .foregroundStyle(vm.fingerDrawingEnabled ? .white : Theme.ink)
                .frame(minWidth: 44, minHeight: 44)
                .background(vm.fingerDrawingEnabled ? Theme.primary : .clear,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .help(vm.fingerDrawingEnabled ? "Đang vẽ bằng ngón tay" : "Chỉ vẽ bằng Pencil")
        .accessibilityLabel("Finger drawing")
    }

    private func toolButton(_ mode: ToolMode) -> some View {
        Button { vm.toolMode = mode } label: {
            Image(systemName: mode.systemImage)
                .foregroundStyle(vm.toolMode == mode ? .white : Theme.ink)
                .frame(minWidth: 44, minHeight: 44)
                .background(vm.toolMode == mode ? Theme.primary : Color.clear,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .accessibilityLabel(mode.title)
    }

    /// Xuất file rồi mở bảng Chia sẻ; lỗi ghi file được báo bằng hộp thoại.
    private func export(_ make: () throws -> [URL]) {
        do {
            exported = ExportedFiles(urls: try make())
        } catch {
            exportError = error.localizedDescription
        }
    }

    /// Occasional actions grouped into an overflow menu to keep the bar uncluttered.
    private var overflowMenu: some View {
        Menu {
            guidesMenuContent
            Divider()
            Button { vm.setFingerDrawing(!vm.fingerDrawingEnabled) } label: {
                Label(vm.fingerDrawingEnabled ? "Vẽ bằng ngón tay: Bật" : "Vẽ bằng ngón tay: Tắt",
                      systemImage: vm.fingerDrawingEnabled ? "hand.draw.fill" : "hand.draw")
            }
            orientationMenuContent
            Menu {
                Button { photoTarget = .insert; showPhotoPicker = true } label: {
                    Label("Chèn ảnh", systemImage: "photo")
                }
                Button { showFileImporter = true } label: {
                    Label("Chèn tệp ảnh", systemImage: "folder")
                }
                Divider()
                Button { photoTarget = .reference; showPhotoPicker = true } label: {
                    Label("Ảnh mẫu để đồ lại", systemImage: "photo.on.rectangle.angled")
                }
            } label: {
                Label("Thêm ảnh", systemImage: "plus.square.on.square")
            }
            Menu {
                Button { export { try [ExportRenderer.pdf(vm.document)] } } label: {
                    Label("PDF – cả sổ (\(vm.pageCount) trang)", systemImage: "doc.richtext")
                }
                Button { export { try ExportRenderer.pngs(vm.document, pages: [vm.currentPage]) } } label: {
                    Label("Ảnh PNG – trang này", systemImage: "photo")
                }
                if vm.pageCount > 1 {
                    Button { export { try ExportRenderer.pngs(vm.document) } } label: {
                        Label("Ảnh PNG – tất cả trang", systemImage: "photo.stack")
                    }
                }
            } label: {
                Label("Xuất & chia sẻ", systemImage: "square.and.arrow.up")
            }
            Button { arImage = vm.exportedImage() } label: {
                Label("Xem bằng AR", systemImage: "arkit")
            }
            Button { vm.save() } label: {
                Label("Lưu", systemImage: "icloud.and.arrow.up")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .help("Thêm")
        .accessibilityLabel("More options")
    }

    private var widthPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            if vm.toolMode == .erase {
                Text("Cỡ tẩy: \(Int(vm.eraseWidth)) pt").font(.subheadline)
                HStack(spacing: 12) {
                    Slider(value: $vm.eraseWidth, in: 4...120)
                    Circle()
                        .stroke(Theme.ink.opacity(0.7), lineWidth: 1.5)
                        .background(Circle().fill(Theme.ink.opacity(0.08)))
                        .frame(width: min(vm.eraseWidth * 0.4, 36) + 6,
                               height: min(vm.eraseWidth * 0.4, 36) + 6)
                        .frame(width: 44, height: 44)
                }
            } else {
                Text("Cỡ cọ: \(Int(vm.width))").font(.subheadline)
                Slider(value: $vm.width, in: 1...60)
            }
        }
        .padding().frame(width: 280)
    }

    /// Rulers, symmetry guides, page templates and filter effects — embedded in
    /// the overflow menu so the top bar stays uncluttered.
    @ViewBuilder
    private var guidesMenuContent: some View {
        Menu("Hướng dẫn & hiệu ứng") {
            Button {
                vm.isRulerActive.toggle()
            } label: {
                Label("Thước kẻ", systemImage: vm.isRulerActive ? "checkmark" : "ruler")
            }

            Menu("Đối xứng") {
                ForEach(SymmetryMode.allCases) { mode in
                    Button { vm.symmetry = mode } label: {
                        Label(mode.title, systemImage: vm.symmetry == mode ? "checkmark" : mode.systemImage)
                    }
                }
            }

            Menu("Đường dựng hình") {
                ForEach(PerspectiveGuide.allCases) { g in
                    Button { vm.perspective = g } label: {
                        Label(g.title, systemImage: vm.perspective == g ? "checkmark" : "skew")
                    }
                }
            }

            Menu("Hiệu ứng lọc") {
                ForEach(SketchFilter.photo) { f in
                    Button { vm.applyFilter(f) } label: { Text(f.title) }
                }
            }

            Menu("Phong cách hội hoạ") {
                ForEach(SketchFilter.painting) { f in
                    Button { vm.applyFilter(f) } label: { Text(f.title) }
                }
            }

            Menu("Biến dạng & làm mờ") {
                ForEach(SketchFilter.distort) { f in
                    Button { vm.applyFilter(f) } label: { Text(f.title) }
                }
            }
        }
    }

    /// Auto / Portrait / Landscape orientation lock.
    @ViewBuilder
    private var orientationMenuContent: some View {
        Menu("Hướng màn hình") {
            Button { orientation.unlock() } label: {
                Label("Tự động", systemImage: !orientation.isLocked ? "checkmark" : "rotate.right")
            }
            Button { orientation.lock(to: .portrait) } label: {
                Label("Dọc", systemImage: orientation.isPortraitLocked ? "checkmark" : "rectangle.portrait")
            }
            Button { orientation.lock(to: .landscape) } label: {
                Label("Khổ ngang", systemImage: orientation.isLandscapeLocked ? "checkmark" : "rectangle")
            }
        }
    }

    // MARK: - Canvas

    private var canvasArea: some View {
        GeometryReader { geo in
            let cs = vm.document.canvasSize
            let fit = min(geo.size.width / cs.width, geo.size.height / cs.height)
            // On-screen (display) size of the canvas; drawing stays in `cs` space.
            let disp = CGSize(width: cs.width * fit, height: cs.height * fit)
            // Effective viewport: the PKCanvasView owns pinch-zoom/pan; every
            // other layer image mirrors its zoom + offset so all layers stay in
            // register (previously only the live ink zoomed, so strokes landed
            // "in the wrong place" relative to the other layers).
            let eff = canvasZoom > 0 ? canvasZoom : fit
            let off = canvasZoom > 0 ? canvasOffset : .zero
            let zf = fit > 0 ? eff / fit : 1
            ZStack {
                // Background + template (zoom-synced)
                Group {
                    Color(hex: vm.document.backgroundHex)
                    Image(uiImage: vm.templateImage(size: cs))
                        .resizable().frame(width: disp.width, height: disp.height)
                }
                .scaleEffect(zf, anchor: .topLeading)
                .offset(x: -off.x, y: -off.y)

                // Layers in order. ONE persistent PencilKit canvas hosts the
                // active layer's ink; all other layers are zoom-synced images.
                layerStack(cs: cs, disp: disp, zf: zf, off: off)

                // Symmetry + perspective/drawing guides (zoom-synced)
                Group {
                    SymmetryGuides(mode: vm.symmetry, size: disp)
                    PerspectiveGuides(guide: vm.perspective, size: disp)
                }
                .scaleEffect(zf, anchor: .topLeading)
                .offset(x: -off.x, y: -off.y)
                .allowsHitTesting(false)

                // Fill tap catcher (only active in fill mode, sits on top).
                // Map the tap from display space back into canvas coordinates.
                if vm.toolMode == .fill {
                    Color.clear.contentShape(Rectangle())
                        .frame(width: disp.width, height: disp.height)
                        .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                            vm.performFill(at: canvasPoint(value.location, eff: eff, off: off))
                        })
                }

                // Shape mode: drag out a bounding rect, then adjust with handles.
                if vm.toolMode == .shape {
                    if vm.pendingShape == nil {
                        shapeDraftCatcher(disp: disp, eff: eff, off: off)
                    } else {
                        ShapeEditingOverlay(vm: vm, scale: fit, displaySize: disp)
                            .frame(width: disp.width, height: disp.height)
                    }
                }

                // Stardust brush: drag to sprinkle stars, baked on release.
                if vm.isStardustActive {
                    stardustCatcher(disp: disp, eff: eff, off: off)
                }
            }
            .frame(width: disp.width, height: disp.height)
            .clipped()
            .frame(width: geo.size.width, height: geo.size.height)
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
            // Double-tap resets pinch-zoom (handled by PencilKit's own scroll
            // zoom — a SwiftUI .scaleEffect here breaks Pencil/touch drawing).
            .onTapGesture(count: 2) { canvasHandle.resetZoom() }
        }
        .padding(16)
    }

    /// All layers in order, split around the single persistent PencilKit
    /// canvas: layers below the active one (and the active layer's raster
    /// contents) render beneath it, layers above render on top. Keeping ONE
    /// canvas across layer/page switches (instead of recreating it inside the
    /// ForEach) preserves zoom and prevents in-flight strokes from committing
    /// to the wrong layer when the active layer changes.
    @ViewBuilder
    private func layerStack(cs: CGSize, disp: CGSize, zf: CGFloat, off: CGPoint) -> some View {
        let layers = vm.document.layers
        let active = vm.activeIndex
        let activeLayer = layers.indices.contains(active) ? layers[active] : nil

        // Below the ink: earlier layers + the active layer's raster contents
        // (fills, filters, imported art).
        ForEach(Array(layers.enumerated()), id: \.element.id) { idx, layer in
            if layer.isVisible && idx <= active {
                if idx == active {
                    if layer.isReference {
                        // A reference selected as the active layer still shows
                        // (the live canvas is hidden/locked for references).
                        zoomSyncedImage(vm.inactiveLayerImage(layer, size: cs),
                                        disp: disp, zf: zf, off: off)
                            .opacity(layer.opacity)
                    } else if let image = layer.image {
                        zoomSyncedImage(image, disp: disp, zf: zf, off: off)
                            .opacity(layer.opacity)
                    }
                } else {
                    zoomSyncedImage(vm.inactiveLayerImage(layer, size: cs),
                                    disp: disp, zf: zf, off: off)
                        .opacity(layer.opacity)
                }
            }
        }

        CanvasView(drawing: Binding(get: { vm.activeDrawing }, set: { vm.activeDrawing = $0 }),
                   tool: vm.currentTool,
                   isRulerActive: vm.isRulerActive,
                   // Allow finger for lasso selection even when finger-drawing is off.
                   pencilOnly: vm.pencilOnly && vm.toolMode != .lasso,
                   symmetry: vm.symmetry,
                   canvasSize: cs,
                   isLocked: (activeLayer?.isLocked ?? true)
                       || !(activeLayer?.isVisible ?? false)
                       || (activeLayer?.isReference ?? false)
                       || vm.toolMode == .fill || vm.toolMode == .shape
                       || vm.isStardustActive,
                   handle: canvasHandle,
                   // Pull firmly past the bottom edge → next page (creates one
                   // past the last); past the top edge → previous page (creates
                   // one before the first) — same as the notepad app.
                   onPullNext: { vm.nextPageOrCreate() },
                   onPullPrevious: { vm.previousPageOrCreate() },
                   onTwoFingerTap: { if vm.canUndo { vm.undo() } },
                   onThreeFingerTap: { if vm.canRedo { vm.redo() } },
                   onPencilAction: { vm.togglePencilEraser() },
                   onViewportChange: { zoom, offset in
                       canvasZoom = zoom
                       canvasOffset = offset
                   })
            .frame(width: disp.width, height: disp.height)
            .opacity((activeLayer?.isVisible ?? false) && !(activeLayer?.isReference ?? false)
                     ? (activeLayer?.opacity ?? 1) : 0)

        // Above the ink: later layers (including any tracing reference).
        ForEach(Array(layers.enumerated()), id: \.element.id) { idx, layer in
            if layer.isVisible && idx > active {
                zoomSyncedImage(vm.inactiveLayerImage(layer, size: cs),
                                disp: disp, zf: zf, off: off)
                    .opacity(layer.opacity)
            }
        }
    }

    /// A non-active layer image, transformed to match the canvas viewport.
    private func zoomSyncedImage(_ image: UIImage, disp: CGSize, zf: CGFloat,
                                 off: CGPoint) -> some View {
        Image(uiImage: image)
            .resizable()
            .frame(width: disp.width, height: disp.height)
            .scaleEffect(zf, anchor: .topLeading)
            .offset(x: -off.x, y: -off.y)
            .allowsHitTesting(false)
    }

    /// Display-space point → canvas coordinates, honoring the live viewport.
    private func canvasPoint(_ p: CGPoint, eff: CGFloat, off: CGPoint) -> CGPoint {
        let s = max(eff, 0.0001)
        return CGPoint(x: (p.x + off.x) / s, y: (p.y + off.y) / s)
    }

    /// Catches the initial drag that lays out a new shape, drawing a live outline
    /// preview until the drag ends (at which point the handle overlay takes over).
    @ViewBuilder
    private func shapeDraftCatcher(disp: CGSize, eff: CGFloat, off: CGPoint) -> some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
                .frame(width: disp.width, height: disp.height)
                .gesture(DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        draftRect = canvasRect(value.startLocation, value.location, eff: eff, off: off)
                    }
                    .onEnded { value in
                        let rect = canvasRect(value.startLocation, value.location, eff: eff, off: off)
                        draftRect = nil
                        if rect.width > 4 || rect.height > 4 { vm.beginShape(rect: rect) }
                    })
            if let dr = draftRect {
                ShapeOutline(kind: vm.shapeKind)
                    .stroke(vm.color, style: StrokeStyle(lineWidth: max(1, vm.shapeStrokeWidth * eff),
                                                         lineCap: .round, lineJoin: .round))
                    .frame(width: dr.width * eff, height: dr.height * eff)
                    .position(x: dr.midX * eff - off.x, y: dr.midY * eff - off.y)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Sprinkles stardust along the drag with a live preview; the stamps are
    /// baked into the layer as strokes when the finger lifts (one undo step).
    @ViewBuilder
    private func stardustCatcher(disp: CGSize, eff: CGFloat, off: CGPoint) -> some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
                .frame(width: disp.width, height: disp.height)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        vm.sprinkleStardust(at: canvasPoint(value.location, eff: eff, off: off),
                                            displayScale: max(eff, 0.0001))
                    }
                    .onEnded { _ in vm.endStardustStroke() })
            Canvas { ctx, _ in
                for stamp in vm.stardustStamps {
                    ctx.fill(Stardust.previewPath(for: stamp, scale: eff),
                             with: .color(vm.color.opacity(stamp.alpha)))
                }
            }
            .frame(width: disp.width, height: disp.height)
            .offset(x: -off.x, y: -off.y)
            .allowsHitTesting(false)
        }
    }

    private func canvasRect(_ a: CGPoint, _ b: CGPoint, eff: CGFloat, off: CGPoint) -> CGRect {
        let pa = canvasPoint(a, eff: eff, off: off)
        let pb = canvasPoint(b, eff: eff, off: off)
        return CGRect(x: min(pa.x, pb.x), y: min(pa.y, pb.y),
                      width: abs(pa.x - pb.x), height: abs(pa.y - pb.y))
    }
}

/// Identifiable wrapper so we can present AR via `fullScreenCover(item:)`.
struct ARImageBox: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Dashed center lines indicating active symmetry axes.
struct SymmetryGuides: View {
    let mode: SymmetryMode
    let size: CGSize

    var body: some View {
        Canvas { ctx, _ in
            var path = Path()
            if mode == .vertical || mode == .quad {
                path.move(to: CGPoint(x: size.width / 2, y: 0))
                path.addLine(to: CGPoint(x: size.width / 2, y: size.height))
            }
            if mode == .horizontal || mode == .quad {
                path.move(to: CGPoint(x: 0, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            }
            ctx.stroke(path, with: .color(Theme.secondary.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 2, dash: [12, 10]))
        }
        .frame(width: size.width, height: size.height)
    }
}
