import SwiftUI

/// 「アプリ内広告ブロック（買い切り）」への入口カード。
///
/// ★**どの画面から出しても同じ形にする**ための共通部品（2026-09-18）。
///   ❌ 完了画面（ブロッカーを ON にした後）にだけ置く
///   → ✅ 準備中の画面にも同じカードを置く
///   → 理由: 入れたばかりの端末は必ず「準備する」画面から始まるので、
///     完了画面にしか無いと**買いたくても入口に辿り着けない**。実際 kureho が
///     シミュレータで探して見つけられなかった（「課金導線どこ？」）。
///     Safari の広告ブロックと違って、この買い切りは**設定を終える前でも使える**。
///
/// ★価格は必ず StoreKit の `displayPrice`（未ロード中はピルを出さない）。
///   値段が見えない行は「設定の続き」に見えて、課金の入口だと気付かれない。
struct ProEntryCard: View {
    let store: ProStore

    var body: some View {
        NavigationLink {
            DNSSettingsView(store: store)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("アプリ内広告ブロック")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("他アプリの広告も抑える（買い切り）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if store.isPro {
                    Text("有効")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                } else if let price = store.proProduct?.displayPrice {
                    Text(price)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.accentColor.opacity(0.12))
                        )
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            .padding(.horizontal, 20)
        }
    }
}
