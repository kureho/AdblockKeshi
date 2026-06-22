import SwiftUI

/// 強力モード（Safari Web Extension）の権限理由とプライバシーをアプリ内で日本語説明するカード。
/// 強力モードは「対象サイトのページを読み取り・変更」する権限が必要になるため、その理由と
/// 取り扱いを明示する（App Store 提出・ユーザー信頼の両面で必須）。
struct StrongModePermissionNote: View {
    private let points: [(String, String)] = [
        ("hand.tap.fill", "ご自身でオンにしたときだけ動作します（初期状態はオフ）。"),
        ("scope", "動くのは「強力ポップアップ対策」で指定した対象サイトだけ。それ以外のサイトには一切関与しません。"),
        ("pause.circle.fill", "サイトごとに一時停止できます（機能拡張のポップアップから操作）。"),
        ("lock.shield.fill", "閲覧履歴・ページの内容・URL を外部に送信しません。記録するのは端末内のブロック件数のみです。")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill").foregroundStyle(Color.accentColor)
                Text("強力モードの権限について")
                    .font(.system(.callout, weight: .semibold))
            }
            Text("タブ乗っ取りを止めるには、対象サイトのページを読み取り・変更する権限が必要です。具体的には次のとおり扱います。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(points, id: \.0) { icon, text in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 18)
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.accentColor.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
    }
}

#Preview {
    StrongModePermissionNote().padding()
}
