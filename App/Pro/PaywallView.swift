import SwiftUI

/// アプリ内広告ブロック（¥800 買い切り）の Paywall。
/// 「あなたが報告するほど、ブロックが増えていく」をヒーローに据える（kureho 決定 A・2026-07-15）。
/// 復元ボタンは商品ロード失敗時でも常に到達可能（2026-01 reject 対策）。訴求規律: 「抑える」+ 限界明記。
struct PaywallView: View {
    let store: ProStore

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                hero
                featureList
                priceSection
                purchaseCTA
                restoreLink
                limitsNote
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
            )
            .padding(20)
        }
        .task { await store.loadProduct() }
    }

    // MARK: - ヘッダー（アイコン + 名称 + 補足／中央寄せ）
    // ★2026-09-16 kureho「中央寄せの方がきれいだね」で横並び（アイコン+名称+価格ピル）から作り替え。
    //   基準は かした・かりた `App/Monetization/PaywallView.swift` の header。
    //   価格はここから priceSection へ移した（横並びをやめると右端の置き場所が無くなるため）。

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("アプリ内広告ブロック")
                .font(.title2.bold())
            Text("端末の中で広告を抑える、買い切りの機能です。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    // MARK: - 価格（header の価格ピルから移設）

    private var priceSection: some View {
        VStack(spacing: 4) {
            if let price = store.proProduct?.displayPrice {
                // ★価格は常に StoreKit の displayPrice。旧仕様にあった "¥800" のフォールバックは
                //   廃止した（largeTitle で大きく出す位置に移ったため、値上げ後に嘘の価格が
                //   大書きされる。他アプリ〈InchCalc / 鏡〉と同じく未ロードなら価格を出さない規律に揃える）。
                Text(price)
                    .font(.largeTitle.bold())
                Text("サブスクではなく、一度きり・月額料金なし")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("価格を取得しています…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    // MARK: - ヒーロー（差別化 #3・報告で増える）

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("あなたが報告するほど、ブロックが増えていく")
                    .font(.system(size: 15, weight: .bold))
            } icon: {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
            }
            Text("届いた報告をもとにフィルタを改善しています。日本のアプリに強い、育つフィルタ。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.06))
        )
    }

    // MARK: - 機能サマリー（4 グループ）

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 10) {
            PaywallFeatureRow(icon: "apps.iphone", text: "他アプリ・Safari の広告を端末内で抑える")
            PaywallFeatureRow(icon: "brain.head.profile", text: "報告で増える 日本語アプリ特化フィルタ")
            PaywallFeatureRow(icon: "lock.shield", text: "端末内処理・外部サーバー非経由（プライバシー）")
            PaywallFeatureRow(icon: "infinity", text: "ずっと買い切り・サブスク化しません")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.06))
        )
    }

    // MARK: - 購入 CTA（状態別）

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
            ctaButton(title: "購入して有効化  →", enabled: !store.isPurchasing, showsSpinner: store.isPurchasing) {
                Task { await store.purchase() }
            }
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

    // MARK: - 復元（常に到達可能）

    private var restoreLink: some View {
        Button("以前ご購入の方はこちら（復元）") {
            Task { await store.restore() }
        }
        .font(.system(size: 12))
        .foregroundStyle(.tertiary)
    }

    // MARK: - 限界明記（訴求規律）

    private var limitsNote: some View {
        Text("※ YouTube・X・Instagram・一部ゲームの広告は仕組み上おさえられません")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.top, 2)
    }
}

private struct PaywallFeatureRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
    }
}
