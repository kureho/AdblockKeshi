import SwiftUI
import KurehoKit

/// アプリ内広告ブロック（買い切り）の Paywall。
///
/// ★2026-09-18 に**対比表（案 B）へ統一**（kureho「文章つらつら並べてて読みづらい」）。
///   旧構成は 見出し + ヒーロー + 便益 4 行 + 価格 + CTA + 復元 + 限界注記 の 7 ブロックで、
///   **どの行も「買うと得られるもの」の言い換え**だった。今は共通部品 `PaywallScaffold` が
///   「無料だとこう / 購入後はこう」の 1 枚にまとめる。画面に出す中身は `ProCatalog` が唯一の出所。
///
/// ★**このアプリだけ KurehoKit を使っていなかった**ので、同日に依存を足して 22 本そろえた。
/// ★ヒーロー（「報告するほど増える」）だけはこのアプリ固有の差別化訴求なので表の上に残す。
/// 復元ボタンは商品ロード失敗時でも常に到達可能（2026-01 reject 対策）＝共通部品が常に出す。
struct PaywallView: View {
    let store: ProStore

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                PaywallScaffold(
                    accent: Color.accentColor,
                    headline: ProCatalog.headline,
                    freeSummary: ProCatalog.freeSummary,
                    features: ProCatalog.rows,
                    paidLabel: ProCatalog.paidLabel,
                    paymentNote: ProCatalog.paymentNote,
                    // 掲出の義務は無い（買い切り 1 本・Schedule 2 §3.8(b)）が、**他アプリと同じく出す**
                    // （2026-09-18「デザイン全然他と揃ってなくない？」）。あみカウントも同じ買い切り
                    // 1 本でここに置いており、買う前にポリシーへ辿れる場所が画面内に無いのは不親切。
                    links: [.privacy(Self.privacyURL)],
                    isRestoring: false,
                    // ★購入中に復元させない（復元は権利集合を全置換するので買い切りごと落ちる）。
                    restoreDisabled: store.isPurchasing,
                    // ★このアプリは見出しの上に自前のヒーローを置くのでアイコンは出さない。
                    showsIcon: false,
                    onRestore: { Task { await store.restore() } }
                ) {
                    purchaseCTA
                }
            }
            // ★**囲みを付けない**（2026-09-18 kureho「デザイン全然他と揃ってなくない？」）。
            //   ❌ 中身ごと角丸カード + 枠線で包む → ✅ 地の上に直接置く
            //   → 理由: 22 本共通の規則は「**囲みは購入ボタンだけ**」
            //     （`~/claude/tasks/paywall-redesign-2026-09-18.md` の確定した理想形）。
            //     このアプリだけ外枠があり、その中にヒーローの囲みも入って**三重の囲み**になっていた。
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            // シートで開いたとき、中身の高さぴったりに縮める（`ProPaywallSheet` と対）。
            .measuringSheetContentHeight()
        }
        // 中身が収まっているときは引っ張れないようにする（他アプリと同じ・ガタつき防止）。
        .scrollBounceBehavior(.basedOnSize)
        .task { await store.loadProduct() }
    }

    /// 設定画面の「プライバシーポリシー」と同じ URL（1 か所で持つ意味は薄いので定数だけ揃える）。
    private static let privacyURL = URL(string: "https://kureho.app/privacy/adblock-keshi")!

    // MARK: - ヒーロー（差別化 #3・報告で増える）

    /// ★**囲まない**（2026-09-18）。他アプリはここが「丸いアイコン 1 個」で、囲みは購入ボタンだけ。
    ///   このアプリだけ薄い色の箱に入っていたので、外枠と合わせて囲みが三重に見えていた。
    ///   アイコンの位置・大きさ・文字の中央揃えは共通部品（`PaywallScaffold` の `showsIcon: true`）
    ///   と同じにして、その上でこのアプリ固有の 1 行（報告で育つ）を足している。
    private var hero: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            // ★1 行だけにする。以前は下に「届いた報告をもとに…育つフィルタ。」の補足が付いていて、
            //   この画面の文章ブロックが 4 つ（ヒーロー 2 + 見出し + 補足）になっていた。
            //   他アプリは 2 つ（見出し + 補足）なので、ここだけ倍の文章量に見えていた。
            Text("報告するほど、ブロックが増えていく")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 購入 CTA（状態別）

    /// ★価格は**この購入ボタンの中**に出す（2026-09-18・22 本共通）。
    ///   ❌ 価格を別ブロック（旧 `priceSection` の largeTitle）で上に置く
    ///   → ✅ 押すボタンと同じ囲みの中で「何をいくらで買うか」を一度に見せる
    ///   → 理由: 囲みは押させたい所 1 箇所だけ（Palmer 1992 / NN/g「罫線は最後の手段」）。
    ///     価格が別の囲みにあると、視線が価格 → 説明 → ボタンと 3 回往復する。
    ///   価格は常に StoreKit の `displayPrice`（未ロードならプレースホルダ・ハードコード禁止）。
    @ViewBuilder
    private var purchaseCTA: some View {
        switch store.loadState {
        case .idle, .loading:
            ctaButton(title: "読み込み中…", enabled: false, showsSpinner: true) {}
        case .failed:
            VStack(spacing: 6) {
                Text("商品情報を取得できませんでした")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("もう一度試す") { Task { await store.loadProduct() } }
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        case .notFound:
            Text("商品を準備中です。しばらくお待ちください。")
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        case .loaded:
            PaywallBuyButton(
                title: "購入して有効化",
                subtitle: "買い切り",
                priceText: store.proProduct?.displayPrice,
                accent: Color.accentColor,
                isBusy: store.isPurchasing
            ) {
                Task { await store.purchase() }
            }
            .disabled(store.isPurchasing)
        }
    }

    private func ctaButton(title: String, enabled: Bool, showsSpinner: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if showsSpinner { ProgressView().tint(.white) }
                Text(title).font(.system(size: 16, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(enabled ? Color.accentColor : Color.accentColor.opacity(0.4))
            )
            .foregroundStyle(.white)
        }
        .disabled(!enabled)
    }

}
