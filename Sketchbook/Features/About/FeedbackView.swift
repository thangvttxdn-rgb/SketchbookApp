import SwiftUI

struct FeedbackView: View {
    /// Hộp thư nhận góp ý — đổi tại đây nếu cần.
    private let feedbackEmail = "nguyenquocthangtxdn@gmail.com"
    @State private var title = ""
    @State private var message = ""

    private var canSend: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Góp ý").font(.largeTitle.bold()).foregroundStyle(Theme.ink)
                Text("Bạn muốn thêm cọ, mẫu giấy hay hiệu ứng nào? Hãy góp ý cho chúng tôi.")
                    .foregroundStyle(Theme.mutedInk)

                VStack(alignment: .leading, spacing: 14) {
                    TextField("Tiêu đề", text: $title)
                        .textFieldStyle(.roundedBorder)
                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("Nội dung góp ý…").foregroundStyle(Theme.mutedInk)
                                .padding(.top, 8).padding(.leading, 5)
                        }
                        TextEditor(text: $message)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 160)
                    }
                    .padding(8)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .appCard()

                Button(action: send) {
                    Label("Gửi qua Email", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white)
                        .padding(.vertical, 14)
                        .background(canSend ? Theme.primary : Theme.mutedInk, in: Capsule())
                }
                .disabled(!canSend)
            }
            .padding(22)
        }
        .background(Theme.background.ignoresSafeArea())
    }

    private func send() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var comps = URLComponents()
        comps.scheme = "mailto"; comps.path = feedbackEmail
        comps.queryItems = [URLQueryItem(name: "subject", value: "Góp ý Vẽ Tranh" + (t.isEmpty ? "" : ": \(t)")),
                            URLQueryItem(name: "body", value: m)]
        if let url = comps.url { UIApplication.shared.open(url) }
    }
}
