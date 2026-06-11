import SwiftUI

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("広告消し")
                    .font(.largeTitle)
                    .bold()
                Text("バージョン \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                    .foregroundColor(.secondary)

                Divider()

                Text("使用フィルタ")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    Text("• EasyList (CC-BY-SA-3.0)")
                    Text("• EasyList Japanese (CC-BY-SA-3.0)")
                    Text("• EasyPrivacy (CC-BY-SA-3.0)")
                    Text("• AdGuard Base Filter (GPL-3.0)")
                    Text("• AdGuard Japanese Filter (GPL-3.0)")
                    Text("• AdGuard Annoyances Filter (GPL-3.0)")
                }
                .font(.body)
                Text("Filter authors: The EasyList authors, AdGuard")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                Text("セキュリティルール提供（v2.0〜）")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    Text("• URLhaus by abuse.ch (CC0 1.0)")
                    Text("• Phishing.Database by Mitchell Krog (MIT)")
                }
                .font(.body)
                Text("Malware data: URLhaus (https://urlhaus.abuse.ch/)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Phishing data: Phishing.Database (https://github.com/mitchellkrogza/Phishing.Database)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                Text("ライセンス全文")
                    .font(.headline)
                NavigationLink("EasyList (CC-BY-SA-3.0)") {
                    LicenseTextView(title: "CC-BY-SA-3.0", filename: "EasyList-CC-BY-SA-3.0")
                }
                NavigationLink("AdGuard Filters (GPL-3.0)") {
                    LicenseTextView(title: "GPL-3.0", filename: "AdGuard-GPL-3.0")
                }
                NavigationLink("SafariConverterLib") {
                    LicenseTextView(title: "SafariConverterLib", filename: "SafariConverterLib-LICENSE")
                }
                NavigationLink("Phishing.Database (MIT)") {
                    LicenseTextView(title: "MIT", filename: "PhishingDatabase-MIT")
                }

                Divider()

                Text("サポート")
                    .font(.headline)
                // ユーザー起点のレビュー導線は requestReview ではなく write-review deep link を使う (Apple 公式推奨)
                Link(destination: URL(string: "https://apps.apple.com/app/id6774906945?action=write-review")!) {
                    Label("レビューを書く", systemImage: "square.and.pencil")
                }
                Link(destination: URL(string: SupportLink.contactURLString)!) {
                    Label("ご意見・お問い合わせ", systemImage: "envelope")
                }
                #if DEBUG
                // シミュレータ確認用 (リリースビルドには含まれない)
                Button {
                    // 実績ありユーザーの見え方を確認するため表示を 23 件に上書き（UserDefaults/DB は変更しない）
                    ReviewPromptCoordinator.shared.debugCountOverride = 23
                    ReviewPromptCoordinator.shared.showSatisfactionPrompt = true
                } label: {
                    Label {
                        Text(verbatim: "（DEBUG）満足度カードを表示")
                    } icon: {
                        Image(systemName: "star.bubble")
                    }
                    .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                #endif

                Spacer()
            }
            .padding()
        }
        .navigationTitle("このアプリについて")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LicenseTextView: View {
    let title: String
    let filename: String

    var body: some View {
        ScrollView {
            Text(loadText())
                .font(.system(.caption, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func loadText() -> String {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "license file not found"
        }
        return text
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
