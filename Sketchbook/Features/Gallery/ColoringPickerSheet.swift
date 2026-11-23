import SwiftUI

/// Chọn một tranh tô màu cho bé. Mở ra là sổ có lớp nét vẽ khoá sẵn;
/// bé chọn công cụ Đổ màu (giọt mực) rồi chạm vào từng vùng để tô.
struct ColoringPickerSheet: View {
    var onPick: (SketchDocument) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 20)]
    private let previews: [ColoringPage: UIImage] = Dictionary(uniqueKeysWithValues: ColoringPage.allCases.map {
        ($0, $0.lineArt(size: CGSize(width: 320, height: 240)))
    })

    var body: some View {
        NavigationStack {
            ScrollView {
                Text("Chạm vào tranh để mở, chọn công cụ Đổ màu rồi chạm vào từng vùng để tô.")
                    .font(.callout).foregroundStyle(Theme.mutedInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.top, 12)
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(ColoringPage.allCases) { page in
                        Button { onPick(page.makeDocument()) } label: {
                            VStack(spacing: 10) {
                                Image(uiImage: previews[page] ?? UIImage())
                                    .resizable().scaledToFit()
                                    .padding(10)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08)))
                                Text(page.title).font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Tô màu cho bé")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
            }
        }
    }
}
