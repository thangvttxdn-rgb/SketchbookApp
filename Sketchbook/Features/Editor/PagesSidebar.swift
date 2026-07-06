import SwiftUI
import UniformTypeIdentifiers

/// Collapsible LEFT sidebar listing every page as a thumbnail. Tap a page to
/// open it, drag to reorder, tap the trash to delete (undoable). Shown on
/// iPad (regular width); collapsed by default.
struct PagesSidebar: View {
    @ObservedObject var vm: EditorViewModel
    var onCollapse: () -> Void

    /// Index being dragged during a reorder.
    @State private var draggingIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                // Identity by page id (NOT index): with index identity, a
                // reorder/delete makes SwiftUI reuse rows for different pages,
                // glitching thumbnails and killing in-flight drags.
                LazyVStack(spacing: 14) {
                    ForEach(Array(vm.document.pages.enumerated()), id: \.element.id) { index, _ in
                        pageCell(index)
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 168)
        .background(Theme.background)
        .overlay(Divider(), alignment: .trailing)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: onCollapse) {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 36, height: 40)
                    .contentShape(Rectangle())
            }
            .help("Hide pages")
            .accessibilityLabel("Hide pages")
            Text("Pages").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            Spacer()
            Button { vm.addPageAfter() } label: {
                Image(systemName: "plus")
                    .font(.headline)
                    .frame(width: 36, height: 40)
                    .contentShape(Rectangle())
            }
            .help("Add page")
            .accessibilityLabel("Add page")
        }
        .padding(.horizontal, 8)
        .background(Theme.surface)
    }

    private func pageCell(_ index: Int) -> some View {
        let isCurrent = index == vm.currentPage
        return VStack(spacing: 6) {
            Image(uiImage: vm.pageThumbnail(index))
                .resizable()
                .scaledToFit()
                .accessibilityIdentifier("pageThumb\(index + 1)")
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isCurrent ? Theme.primary : Theme.ink.opacity(0.15),
                                lineWidth: isCurrent ? 3 : 1)
                )
                .overlay(alignment: .topTrailing) {
                    Button { vm.deletePage(at: index) } label: {
                        Image(systemName: "trash.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red.opacity(0.85))
                            .shadow(color: .black.opacity(0.25), radius: 2)
                            .padding(5)
                    }
                    .accessibilityLabel("Delete page \(index + 1)")
                }
            Text("\(index + 1)")
                .font(.caption.weight(isCurrent ? .bold : .regular))
                .foregroundStyle(isCurrent ? Theme.primary : Theme.mutedInk)
        }
        .contentShape(Rectangle())
        // onDrag must come BEFORE any tap handling — a plain .onTapGesture on
        // the same view blocks the long-press drag lift. The tap is attached
        // as a simultaneous gesture instead.
        .onDrag {
            draggingIndex = index
            return NSItemProvider(object: "\(index)" as NSString)
        }
        .onDrop(of: [UTType.text], delegate: PageDropDelegate(index: index,
                                                              draggingIndex: $draggingIndex,
                                                              vm: vm))
        .simultaneousGesture(TapGesture().onEnded { vm.goToPage(index) })
    }
}

/// Reorders live while the drag hovers over other cells.
private struct PageDropDelegate: DropDelegate {
    let index: Int
    @Binding var draggingIndex: Int?
    let vm: EditorViewModel

    func dropEntered(info: DropInfo) {
        guard let from = draggingIndex, from != index else { return }
        vm.movePage(fromIndex: from, toIndex: index)
        draggingIndex = index
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        draggingIndex = nil
        vm.endPageReorder()
        Haptics.select()
        return true
    }
}
