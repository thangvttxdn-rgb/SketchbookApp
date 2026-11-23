import SwiftUI

struct AboutView: View {
    private let upstreamURL = URL(string: "https://github.com/alfredang/sketchbookapp")!
    private var versionString: String {
        let i = Bundle.main.infoDictionary
        let s = i?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = i?["CFBundleVersion"] as? String ?? "1"
        return "\(s) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Giới thiệu").font(.largeTitle.bold()).foregroundStyle(Theme.ink)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Vẽ Tranh").font(.title3.bold()).foregroundStyle(Theme.ink)
                    Text("Ứng dụng vẽ cho iPad: cọ cảm ứng lực với Apple Pencil, nhiều lớp, đồ lại ảnh mẫu, vẽ đối xứng, thước kẻ, đổ màu và hiệu ứng lọc. Có thêm vẽ kỹ thuật (lưới mm, khung bản vẽ, ghi kích thước), ghi chú lên ảnh và PDF, xuất PDF nhiều trang, tranh tô màu cho bé. Dữ liệu đồng bộ qua iCloud cá nhân.")
                        .foregroundStyle(Theme.mutedInk)
                }
                .appCard()

                Text("ĐƠN VỊ PHÁT TRIỂN").font(.caption.weight(.semibold)).foregroundStyle(Theme.mutedInk)
                VStack(alignment: .leading, spacing: 0) {
                    Label("Chi nhánh Toa xe Đà Nẵng", systemImage: "building.2.fill")
                        .foregroundStyle(Theme.ink)
                        .padding(.vertical, 14)
                    Divider()
                    Text("Phát triển từ Sketchbook Studio © Tertiary Infotech Academy Pte Ltd, giấy phép MIT.")
                        .font(.footnote).foregroundStyle(Theme.mutedInk)
                        .padding(.vertical, 14)
                    Link(destination: upstreamURL) {
                        Label("Mã nguồn gốc trên GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                            .foregroundStyle(Theme.primary)
                    }
                    .padding(.bottom, 14)
                }
                .appCard()

                HStack {
                    Text("Phiên bản").foregroundStyle(Theme.ink)
                    Spacer()
                    Text(versionString).foregroundStyle(Theme.mutedInk)
                }
                .appCard()
            }
            .padding(22)
        }
        .background(Theme.background.ignoresSafeArea())
    }
}
