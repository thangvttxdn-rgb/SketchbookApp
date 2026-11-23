import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct GalleryView: View {
    @EnvironmentObject private var store: DocumentStore
    @State private var newSketch: SketchDocument?
    @State private var openSketch: SketchDocument?
    @State private var showingNewSheet = false
    @State private var showingSettings = false
    @State private var showingColoring = false
    @State private var showingPDFImporter = false
    @State private var showingPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var importMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 20)]

    /// Favorites first, then most-recently modified.
    private var sortedDocuments: [SketchDocument] {
        store.documents.sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            return $0.modifiedAt > $1.modifiedAt
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if store.documents.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(sortedDocuments) { doc in
                            SketchCell(document: doc) { store.toggleFavorite(doc) }
                                .onTapGesture { openSketch = doc }
                                .contextMenu {
                                    Button { openSketch = doc } label: { Label("Mở", systemImage: "pencil") }
                                    Button { store.toggleFavorite(doc) } label: {
                                        Label(doc.isFavorite ? "Bỏ yêu thích" : "Yêu thích",
                                              systemImage: doc.isFavorite ? "star.slash" : "star")
                                    }
                                    Button { store.duplicate(doc) } label: { Label("Nhân bản", systemImage: "plus.square.on.square") }
                                    Button(role: .destructive) { store.delete(doc) } label: { Label("Xoá", systemImage: "trash") }
                                }
                        }
                    }
                    .padding(20)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Tranh vẽ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showingNewSheet = true } label: { Label("Bản vẽ mới", systemImage: "square.and.pencil") }
                        Button { showingPDFImporter = true } label: { Label("Ghi chú lên PDF", systemImage: "doc.text") }
                        Button { showingPhotoPicker = true } label: { Label("Ghi chú lên ảnh", systemImage: "photo") }
                        Button { showingColoring = true } label: { Label("Tô màu cho bé", systemImage: "paintpalette") }
                    } label: { Label("Mới", systemImage: "plus") }
                }
            }
            .sheet(isPresented: $showingNewSheet) {
                NewSketchSheet { doc in
                    let saved = store.save(doc)
                    showingNewSheet = false
                    openSketch = saved
                }
            }
            .sheet(isPresented: $showingColoring) {
                ColoringPickerSheet { doc in
                    let saved = store.save(doc)
                    showingColoring = false
                    openSketch = saved
                }
            }
            .fileImporter(isPresented: $showingPDFImporter, allowedContentTypes: [.pdf]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let (doc, skipped) = try AnnotationImporter.document(fromPDF: url)
                    openSketch = store.save(doc)
                    if skipped > 0 {
                        importMessage = "PDF dài hơn \(AnnotationImporter.maxPDFPages) trang: đã mở \(AnnotationImporter.maxPDFPages) trang đầu, bỏ qua \(skipped) trang."
                    }
                } catch {
                    importMessage = error.localizedDescription
                }
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                photoItem = nil
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        openSketch = store.save(AnnotationImporter.document(fromImage: image, title: "Ghi chú ảnh"))
                    } else {
                        importMessage = "Không mở được ảnh này."
                    }
                }
            }
            .alert("Thông báo", isPresented: Binding(get: { importMessage != nil },
                                                    set: { if !$0 { importMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importMessage ?? "")
            }
            .fullScreenCover(item: $openSketch) { doc in
                EditorView(document: doc)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView().environmentObject(store)
            }
            .task {
                await store.reload()
                if ProcessInfo.processInfo.environment["SKETCH_OPEN"] == "1" {
                    openSketch = store.documents.first
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "scribble.variable")
                .font(.system(size: 64)).foregroundStyle(Theme.primary)
            Text("Chưa có tranh nào").font(.title2.bold()).foregroundStyle(Theme.ink)
            Text("Chạm + để bắt đầu bức tranh đầu tiên.").foregroundStyle(Theme.mutedInk)
            Button { showingColoring = true } label: {
                Label("Tô màu cho bé", systemImage: "paintpalette")
            }
            Button { showingNewSheet = true } label: {
                Label("Bản vẽ mới", systemImage: "plus")
                    .foregroundStyle(.white).padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Theme.primary, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }
}

struct SketchCell: View {
    let document: SketchDocument
    var onToggleFavorite: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface)
                    if let thumb = document.thumbnail {
                        Image(uiImage: thumb).resizable().scaledToFit().padding(8)
                    } else {
                        Image(systemName: "photo").font(.largeTitle).foregroundStyle(Theme.mutedInk)
                    }
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.06)))

                Button(action: onToggleFavorite) {
                    Image(systemName: document.isFavorite ? "star.fill" : "star")
                        .font(.subheadline)
                        .foregroundStyle(document.isFavorite ? Theme.highlight : .white)
                        .padding(7)
                        .background(.black.opacity(0.28), in: Circle())
                }
                .padding(8)
            }

            Text(document.title).font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink).lineLimit(1)
            Text(document.modifiedAt, style: .date).font(.caption).foregroundStyle(Theme.mutedInk)
        }
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 3)
    }
}
