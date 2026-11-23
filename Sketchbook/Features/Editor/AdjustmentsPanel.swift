import SwiftUI
import UIKit

/// Procreate-style Adjustments: pick an adjustment, tune its sliders against a
/// live preview of the active layer, then Apply (a single undoable step).
struct AdjustmentsPanel: View {
    @ObservedObject var vm: EditorViewModel
    /// True when docked in the iPad side panel (no Done button; Apply pops
    /// back to the list instead of dismissing a sheet).
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @State private var path: [SketchAdjustment] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                section("Màu sắc", SketchAdjustment.color)
                section("Làm mờ", SketchAdjustment.blur)
                section("Cách điệu", SketchAdjustment.stylize)
            }
            .navigationTitle("Điều chỉnh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !embedded {
                    ToolbarItem(placement: .cancellationAction) { Button("Xong") { dismiss() } }
                }
            }
            .navigationDestination(for: SketchAdjustment.self) { adj in
                AdjustmentDetail(vm: vm, adjustment: adj) {
                    if embedded { path.removeAll() } else { dismiss() }
                }
            }
        }
    }

    private func section(_ title: String, _ items: [SketchAdjustment]) -> some View {
        Section(title) {
            ForEach(items) { adj in
                NavigationLink(value: adj) {
                    Label(adj.title, systemImage: adj.systemImage)
                        .foregroundStyle(Theme.ink)
                }
            }
        }
    }
}

/// Slider page for one adjustment with a live before/after preview.
struct AdjustmentDetail: View {
    @ObservedObject var vm: EditorViewModel
    let adjustment: SketchAdjustment
    var onApplied: () -> Void

    @State private var params: [String: Double] = [:]
    @State private var baseImage: UIImage?
    @State private var previewImage: UIImage?
    /// Debounce so a fast slider drag doesn't queue dozens of CI renders.
    @State private var previewTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                preview
                controls
                Button {
                    vm.applyAdjustment(adjustment, params: params)
                    onApplied()
                } label: {
                    Text("Áp dụng")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.white)
                }
                Text("Áp dụng cho lớp hiện tại. Dùng Hoàn tác để quay lại.")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle(adjustment.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            params = adjustment.defaultParams
            baseImage = vm.adjustmentPreviewBase()
            refreshPreview()
        }
    }

    private var preview: some View {
        ZStack {
            CheckerboardBackground()
            if let img = previewImage ?? baseImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Theme.ink.opacity(0.1), lineWidth: 1))
    }

    private var controls: some View {
        VStack(spacing: 14) {
            ForEach(adjustment.parameters) { param in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(param.label).font(.subheadline).foregroundStyle(Theme.ink)
                        Spacer()
                        Text(valueLabel(param))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.mutedInk)
                    }
                    Slider(value: binding(param), in: param.range)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func valueLabel(_ param: AdjustmentParam) -> String {
        let v = params[param.key] ?? param.initial
        let text = param.range.upperBound - param.range.lowerBound <= 4
            ? String(format: "%.2f", v)
            : String(Int(v))
        return text + param.unit
    }

    private func binding(_ param: AdjustmentParam) -> Binding<Double> {
        Binding(get: { params[param.key] ?? param.initial },
                set: { params[param.key] = $0; refreshPreview() })
    }

    private func refreshPreview() {
        guard let base = baseImage else { return }
        let adj = adjustment
        let p = params
        previewTask?.cancel()
        previewTask = Task {
            let img = await Task.detached(priority: .userInitiated) {
                AdjustmentEngine.apply(adj, to: base, params: p)
            }.value
            if !Task.isCancelled { previewImage = img }
        }
    }
}

/// Light checkerboard so transparent layer areas read as transparent.
struct CheckerboardBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let cell: CGFloat = 10
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = 0
                var col = 0
                while x < size.width {
                    if (row + col).isMultiple(of: 2) {
                        ctx.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)),
                                 with: .color(Color.gray.opacity(0.15)))
                    }
                    x += cell; col += 1
                }
                y += cell; row += 1
            }
        }
        .background(Theme.surface)
    }
}
