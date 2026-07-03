import SwiftUI

/// Sheet wrapper used on iPhone (compact width). Reusable content lives in
/// `ShapesPickerContent` so the iPad side panel can embed it too.
struct ShapesPanel: View {
    @ObservedObject var vm: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ShapesPickerContent(vm: vm)
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle("Shapes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
    }
}

/// Vector-shape picker: choose a shape, set the outline width + colour, and an
/// optional solid fill colour. Selecting a shape switches the editor into shape
/// mode; the user then drags it out on the canvas and adjusts the handles.
struct ShapesPickerContent: View {
    @ObservedObject var vm: EditorViewModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("SHAPE").font(.caption.weight(.semibold)).foregroundStyle(Theme.mutedInk)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(ShapeKind.allCases) { kind in
                        shapeCell(kind)
                    }
                }

                Text("OUTLINE").font(.caption.weight(.semibold)).foregroundStyle(Theme.mutedInk)
                VStack(spacing: 12) {
                    HStack {
                        ColorPicker("Stroke color", selection: $vm.color, supportsOpacity: true)
                    }
                    HStack(spacing: 12) {
                        Text("Width").font(.subheadline).foregroundStyle(Theme.ink)
                        Slider(value: $vm.width, in: 1...60)
                        Text("\(Int(vm.width)) pt").font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.ink).frame(width: 46, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text("FILL").font(.caption.weight(.semibold)).foregroundStyle(Theme.mutedInk)
                VStack(spacing: 12) {
                    Toggle(isOn: $vm.shapeFillEnabled) {
                        Text("Fill shape").font(.subheadline).foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.primary)
                    if vm.shapeFillEnabled {
                        ColorPicker("Fill color", selection: $vm.shapeFillColor, supportsOpacity: true)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .opacity(vm.shapeKind.canFill ? 1 : 0.4)
                .disabled(!vm.shapeKind.canFill)

                Text("Drag on the canvas to place the shape, then rotate, resize or flip with the handles.")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
            }
            .padding(16)
        }
        .background(Theme.background)
    }

    private func shapeCell(_ kind: ShapeKind) -> some View {
        let selected = vm.toolMode == .shape && vm.shapeKind == kind
        return Button {
            vm.selectShape(kind)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(selected ? .white : Theme.primary)
                Text(kind.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(selected ? .white : Theme.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(selected ? Theme.primary : Theme.surface,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityLabel(kind.title)
    }
}
