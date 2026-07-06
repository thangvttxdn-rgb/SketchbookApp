import SwiftUI

/// Sheet wrapper used on iPhone (compact width). The reusable picker content
/// lives in `BrushPickerContent` so the iPad side panel can embed it too.
struct BrushPanel: View {
    @ObservedObject var vm: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BrushPickerContent(vm: vm)
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle("Brushes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
    }
}

/// The scrollable brush + pencil + size picker, embeddable anywhere.
struct BrushPickerContent: View {
    @ObservedObject var vm: EditorViewModel

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("SIZE").font(.caption.weight(.semibold)).foregroundStyle(Theme.mutedInk)
                    HStack(spacing: 12) {
                        Slider(value: $vm.width, in: 1...60)
                        Text("\(Int(vm.width)) pt").font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.ink).frame(width: 52, alignment: .trailing)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    ForEach(BrushType.Category.allCases) { category in
                        Text(category.rawValue.uppercased())
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.mutedInk)
                            .padding(.top, 4)
                        ForEach(BrushType.allCases.filter { $0.category == category && $0 != .pencil }) { brush in
                            brushRow(brush)
                        }
                    }

                    Text("PENCILS").font(.caption.weight(.semibold)).foregroundStyle(Theme.mutedInk)
                        .padding(.top, 8)
                    ForEach(PencilGrade.allCases) { grade in
                        Button {
                            vm.selectPencilGrade(grade)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "pencil")
                                    .font(.title3).frame(width: 28)
                                    .foregroundStyle(vm.pencilGrade == grade ? .white : Theme.primary)
                                Text("Pencil \(grade.title)")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(vm.pencilGrade == grade ? .white : Theme.ink)
                                    .frame(width: 84, alignment: .leading)
                                PencilStrokePreview(grade: grade)
                                    .frame(height: 30).frame(maxWidth: .infinity)
                                if vm.pencilGrade == grade { Image(systemName: "checkmark").foregroundStyle(.white) }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(vm.pencilGrade == grade ? Theme.primary : Theme.surface,
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
                .padding(16)
        }
    }

    @ViewBuilder
    private func brushRow(_ brush: BrushType) -> some View {
        Button {
            vm.selectBrush(brush)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: brush.systemImage)
                    .font(.title3).frame(width: 28)
                    .foregroundStyle(isSelectedBrush(brush) ? .white : Theme.primary)
                Text(brush.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isSelectedBrush(brush) ? .white : Theme.ink)
                    .frame(width: 110, alignment: .leading)
                BrushStrokePreview(brush: brush, color: vm.color)
                    .frame(height: 30).frame(maxWidth: .infinity)
                if isSelectedBrush(brush) { Image(systemName: "checkmark").foregroundStyle(.white) }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(isSelectedBrush(brush) ? Theme.primary : Theme.surface,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func isSelectedBrush(_ brush: BrushType) -> Bool {
        vm.brush == brush && vm.pencilGrade == nil
    }
}

/// Preview squiggle for a graphite pencil grade (darkness + width).
struct PencilStrokePreview: View {
    let grade: PencilGrade
    var body: some View {
        Canvas { ctx, size in
            let midY = size.height / 2
            var p = Path()
            p.move(to: CGPoint(x: 6, y: midY))
            p.addCurve(to: CGPoint(x: size.width - 6, y: midY),
                       control1: CGPoint(x: size.width * 0.33, y: midY - size.height * 0.42),
                       control2: CGPoint(x: size.width * 0.66, y: midY + size.height * 0.42))
            ctx.stroke(p, with: .color(grade.color.opacity(0.8)),
                       style: StrokeStyle(lineWidth: grade.width, lineCap: .round, lineJoin: .round))
        }
    }
}

/// A sample squiggle rendered with each brush's characteristic width and opacity
/// so the brushes are visually distinguishable (icons alone read as similar).
struct BrushStrokePreview: View {
    let brush: BrushType
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            let midY = size.height / 2
            var p = Path()
            p.move(to: CGPoint(x: 6, y: midY))
            p.addCurve(to: CGPoint(x: size.width - 6, y: midY),
                       control1: CGPoint(x: size.width * 0.33, y: midY - size.height * 0.42),
                       control2: CGPoint(x: size.width * 0.66, y: midY + size.height * 0.42))
            let w = min(brush.defaultWidth, 22)
            ctx.stroke(p, with: .color(color.opacity(brush.opacity)),
                       style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        }
    }
}

struct LayersPanel: View {
    @ObservedObject var vm: EditorViewModel
    /// When embedded in the iPad side panel we don't take the full title size.
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @State private var groupingIndex: Int?
    @State private var newGroupName = ""
    @State private var renamingIndex: Int?
    @State private var newLayerName = ""

    var body: some View {
        NavigationStack {
            List {
                if vm.referenceLayerIndex != nil {
                    Section("Reference Overlay") {
                        VStack(alignment: .leading) {
                            Text("Tracing opacity: \(Int(vm.referenceOpacity * 100))%")
                                .font(.caption).foregroundStyle(Theme.mutedInk)
                            Slider(value: Binding(get: { vm.referenceOpacity },
                                                  set: { vm.updateReferenceOpacity($0) }), in: 0...1)
                        }
                    }
                }

                if !vm.groupNames.isEmpty {
                    Section("Groups") {
                        ForEach(vm.groupNames, id: \.self) { group in
                            HStack {
                                Image(systemName: "folder").foregroundStyle(Theme.primary)
                                Text(group).foregroundStyle(Theme.ink)
                                Spacer()
                                Button { vm.toggleGroupVisibility(group) } label: {
                                    Image(systemName: "eye").foregroundStyle(Theme.mutedInk)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("Layers") {
                    ForEach(Array(vm.document.layers.enumerated()), id: \.element.id) { idx, layer in
                        LayerRow(vm: vm, index: idx, layer: layer,
                                 onGroup: {
                                     groupingIndex = idx
                                     newGroupName = layer.groupName ?? ""
                                 },
                                 onRename: {
                                     renamingIndex = idx
                                     newLayerName = layer.name
                                 })
                    }
                    .onDelete { offsets in offsets.forEach { vm.deleteLayer(at: $0) } }
                    .onMove { source, dest in vm.moveLayer(from: source, to: dest) }
                }
                Text("Tap a layer to select it. Hold and drag to reorder; swipe left to delete.")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
                    .listRowBackground(Color.clear)
            }
            .navigationTitle("Layers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { vm.duplicateActiveLayer() } label: { Image(systemName: "plus.square.on.square") }
                    Button { vm.addLayer() } label: { Image(systemName: "plus") }
                }
            }
            .alert("Group Name", isPresented: Binding(get: { groupingIndex != nil },
                                                      set: { if !$0 { groupingIndex = nil } })) {
                TextField("Group name (empty to ungroup)", text: $newGroupName)
                Button("Save") {
                    if let i = groupingIndex { vm.setGroup(at: i, to: newGroupName) }
                    groupingIndex = nil
                }
                Button("Cancel", role: .cancel) { groupingIndex = nil }
            }
            .alert("Rename Layer", isPresented: Binding(get: { renamingIndex != nil },
                                                        set: { if !$0 { renamingIndex = nil } })) {
                TextField("Layer name", text: $newLayerName)
                Button("Save") {
                    if let i = renamingIndex, !newLayerName.trimmingCharacters(in: .whitespaces).isEmpty {
                        vm.renameLayer(at: i, to: newLayerName)
                    }
                    renamingIndex = nil
                }
                Button("Cancel", role: .cancel) { renamingIndex = nil }
            }
        }
    }
}

struct LayerRow: View {
    @ObservedObject var vm: EditorViewModel
    let index: Int
    let layer: Layer
    var onGroup: () -> Void
    var onRename: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                vm.document.layers[index].isVisible.toggle()
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(Theme.mutedInk)
            }
            .buttonStyle(.plain)

            // Procreate-style content preview.
            Image(uiImage: vm.layerThumbnail(index))
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 34)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Theme.ink.opacity(0.15), lineWidth: 0.5))
                .opacity(layer.isVisible ? 1 : 0.35)

            // Plain text (NOT a TextField): tapping a row must select the
            // layer, never focus a text editor / pop the keyboard. Renaming
            // lives behind the row menu.
            VStack(alignment: .leading, spacing: 2) {
                Text(layer.name)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let g = layer.groupName {
                        Label(g, systemImage: "folder").font(.caption2).foregroundStyle(Theme.secondary)
                    }
                    if layer.isReference {
                        Text("Reference").font(.caption2).foregroundStyle(Theme.secondary)
                    }
                    if layer.isLocked {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(Theme.secondary)
                    }
                }
            }
            Spacer(minLength: 0)

            if index == vm.activeIndex {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.primary)
            }
            Menu {
                Button { vm.setActiveLayer(index) } label: { Label("Select", systemImage: "hand.tap") }
                Button(action: onRename) { Label("Rename…", systemImage: "pencil") }
                Button(action: onGroup) { Label("Move to Group…", systemImage: "folder.badge.plus") }
                if layer.groupName != nil {
                    Button { vm.setGroup(at: index, to: nil) } label: { Label("Ungroup", systemImage: "folder.badge.minus") }
                }
                Button { vm.document.layers[index].isLocked.toggle() } label: {
                    Label(layer.isLocked ? "Unlock" : "Lock", systemImage: layer.isLocked ? "lock.open" : "lock")
                }
                Menu {
                    ForEach([1.0, 0.75, 0.5, 0.25], id: \.self) { value in
                        Button {
                            vm.document.layers[index].opacity = value
                        } label: {
                            Label("\(Int(value * 100))%",
                                  systemImage: abs(layer.opacity - value) < 0.01 ? "checkmark" : "circle.lefthalf.filled")
                        }
                    }
                } label: {
                    Label("Opacity", systemImage: "circle.lefthalf.filled")
                }
                Button(role: .destructive) { vm.deleteLayer(at: index) } label: {
                    Label("Delete Layer", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(Theme.mutedInk)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { vm.setActiveLayer(index) }
    }
}
