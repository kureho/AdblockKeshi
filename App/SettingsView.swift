import SwiftUI
import KurehoKit

/// 設定タブ。
///
/// ★2026-09-18 に新設（kureho「設定のページ追加しよう。他と同じにしたほうが体験もいい」）。
///   それまでこのアプリだけ設定画面が無く、買い切りの入口が**完了画面（Safari の設定を
///   終えた後の画面）にしか無かった**＝入れたばかりの端末からは辿り着けなかった。
///   他 21 本と同じく「設定タブの一番上に課金カード」に揃える。
///
/// ★あしらいは全アプリ共通の標準パターン（memory `feedback_plus_upgrade_card_pattern`）＝
///   アイコン / 価格ピル / 機能サマリー / CTA / 復元 の 5 要素。
struct SettingsView: View {
    /// アプリ全体で 1 つの `ProStore`（`AdblockKeshiApp` が持つ）。
    let proStore: ProStore

    @State private var siteExceptionDomains: [String] = []
    @State private var restoreMessage: String?
    @State private var isRestoring = false
    /// 購入シートの開閉。★他 21 本と同じく **CTA はシートを開く**（画面遷移にしない）。
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SettingsLayout.sectionSpacing) {
                    proSection

                    if !siteExceptionDomains.isEmpty {
                        SettingsSection(
                            header: "ブロックを止めているサイト",
                            footer: "壊れ報告のときに「一時オフ」にしたサイトです。ここから戻せます。"
                        ) {
                            SettingsRow(isLast: true) {
                                NavigationLink {
                                    SiteExceptionsListView(onChange: reloadSiteExceptions)
                                } label: {
                                    HStack {
                                        Text("停止中のサイト")
                                        Spacer(minLength: 12)
                                        Text("\(siteExceptionDomains.count) 件")
                                            .foregroundStyle(.secondary)
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    SettingsSection(header: "お問い合わせ") {
                        SettingsRow {
                            Button {
                                SupportLink.openContact()
                            } label: {
                                Label("要望・不具合を送る", systemImage: "envelope")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                        }
                        SettingsRow {
                            Link(destination: Self.reviewURL) {
                                Label("レビューを書く", systemImage: "square.and.pencil")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                        }
                        // Apple はポリシーへのリンクを ASC のメタデータと**アプリの中の両方**に
                        // 求めている（App Review Guidelines 5.1.1(i)）。
                        SettingsRow(isLast: true) {
                            Link(destination: Self.privacyURL) {
                                Label("プライバシーポリシー", systemImage: "hand.raised")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                        }
                    }

                    SettingsSection {
                        SettingsRow {
                            NavigationLink {
                                AboutView()
                            } label: {
                                HStack {
                                    Text("このアプリについて")
                                    Spacer(minLength: 12)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        SettingsRow {
                            SettingsValueRow(title: "バージョン", value: Self.versionText)
                        }
                        SettingsRow(isLast: true) {
                            Text("© 2026 KUREHO")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.vertical, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingPaywall) {
                ProPaywallSheet(store: proStore)
            }
            .alert("購入の復元", isPresented: .constant(restoreMessage != nil)) {
                Button("OK") { restoreMessage = nil }
            } message: {
                Text(restoreMessage ?? "")
            }
            .onAppear(perform: reloadSiteExceptions)
            .task {
                // ★ここで**所有を StoreKit に問い合わせない**（2026-09-18）。
                //   `Transaction.currentEntitlements` / `AppTransaction.shared` は
                //   Apple Account が無い端末で**サインインのダイアログを出す**。設定を開いただけで
                //   それが出るのはおかしいので、所有は端末のキャッシュ（`ProStore.isPro`）で判断し、
                //   実際の問い合わせは**買う直前**（`DNSSettingsView`）と「購入を復元」に寄せる。
                //   ❌ 画面を開いたら念のため最新化 → ✅ 買う/復元のときだけ聞く
                guard !ScreenshotMode.isActive else { return }
                proStore.startTransactionListener()
                // 価格ピルのための商品取得だけ（こちらはサインインを要求しない）。
                if !proStore.isPro { await proStore.loadProduct() }
            }
        }
    }

    private func reloadSiteExceptions() {
        siteExceptionDomains = SiteExceptionsStore.sharedAppGroup()?.readDomains() ?? []
    }

    // MARK: - 課金カード（標準 5 要素）

    @ViewBuilder
    private var proSection: some View {
        Group {
            if proStore.isPro {
                ownedCard
            } else {
                upgradeCard
            }
        }
        .padding(.horizontal, SettingsLayout.cardHInset)
    }

    private var upgradeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                iconBadge
                Text("アプリ内広告ブロック")
                    .font(.system(size: 17, weight: .heavy))
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    // ★価格は常に StoreKit の displayPrice（ハードコード禁止）。
                    Text(proStore.proProduct?.displayPrice ?? "—")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Color.accentColor)
                    Text("買い切り")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                }
            }
            featureBlock
            Text("サブスクではなく、一度きり。")
                .font(.caption.weight(.heavy))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
            // ★`NavigationLink` にしない（設定画面へ push すると他アプリと押した後が変わる）。
            Button {
                showingPaywall = true
            } label: {
                Text("詳しく見る →")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settingsProCard")
            restoreButton
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: SettingsLayout.cardRadius, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground)))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsLayout.cardRadius, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var iconBadge: some View {
        RoundedRectangle(cornerRadius: 38 * 0.28, style: .continuous)
            .fill(Color.accentColor.opacity(0.15))
            .frame(width: 38, height: 38)
            .overlay(
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            )
            .accessibilityHidden(true)
    }

    /// 機能サマリー。**購入画面 `PaywallView` の表と 1 対 1**（`ProCatalog` が唯一の出所）。
    private var featureBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(ProCatalog.rows) { row in
                HStack(spacing: 10) {
                    Image(systemName: row.symbol)
                        .font(.footnote)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    Text("\(row.title)を\(row.plus)")
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.accentColor.opacity(0.06)))
    }

    /// 購入済みの表示（**復元ボタンは置かない** ＝ 標準パターン）。
    private var ownedCard: some View {
        NavigationLink {
            DNSSettingsView(store: proStore)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .overlay(Image(systemName: "checkmark").font(.footnote.weight(.heavy)).foregroundStyle(.white))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("アプリ内広告ブロック ご利用中")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(.primary)
                    Text("他アプリの広告を端末内で抑えます。オン・オフはここから。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: SettingsLayout.cardRadius, style: .continuous)
                .fill(Color.accentColor.opacity(0.08)))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsLayout.cardRadius, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var restoreButton: some View {
        Button {
            Task {
                // 結果を捨てると、押しても何も起きないように見える。
                isRestoring = true
                await proStore.restore()
                isRestoring = false
                restoreMessage = proStore.isPro
                    ? "アプリ内広告ブロックを復元しました。"
                    : "この Apple ID では、復元できる購入が見つかりませんでした。"
            }
        } label: {
            Text(isRestoring ? "復元中…" : "購入済みの方は復元")
                .font(.caption)
                .foregroundStyle(.secondary)
                // frame が無いとグリフ範囲だけが当たり判定になる（他アプリと同じ作法）。
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRestoring || proStore.isPurchasing)
        .accessibilityIdentifier("settingsRestoreButton")
    }

    // MARK: - 定数

    private static let privacyURL = URL(string: "https://kureho.app/privacy/adblock-keshi")!
    private static let reviewURL = URL(string: "https://apps.apple.com/app/id6774906945?action=write-review")!

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }
}

// MARK: - 設定画面の自前カード（角丸 10pt 統一・2026-09-15 kureho 決定）
//
// iOS 26 の List/Form はセクション背景を角丸約 18pt でクリップし、アプリ側から角丸を指定する
// 公式 API が無い。全アプリ角丸 10pt に統一するため ScrollView + 自前カードで組む。
// 余白は iOS 26 の inset grouped List をピクセル実測して合わせた値（他アプリと同一）。

/// 設定画面のレイアウト定数。
enum SettingsLayout {
    /// カード角丸。全アプリ共通 10pt。
    static let cardRadius: CGFloat = 10
    /// 画面端からカード端までの余白（標準の inset grouped と同じ）。
    static let cardHInset: CGFloat = 16
    /// カード内の行の左右余白。見出し／補足文もこの位置に揃える。
    static let rowHPadding: CGFloat = 16
    /// 行の最小高さ（文字だけの行＝標準 44pt）。
    static let rowMinHeight: CGFloat = 44
    /// 行の上下余白。
    static let rowVPadding: CGFloat = 12
    /// 見出しとカード上端の間隔。
    static let headerBottom: CGFloat = 12
    /// カード下端と補足文の間隔。
    static let footerTop: CGFloat = 8
    /// セクション間の間隔。
    static let sectionSpacing: CGFloat = 16
}

/// 設定画面の 1 セクション（見出し＋角丸カード＋補足文）。
struct SettingsSection<Content: View>: View {
    var header: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                Text(header)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, SettingsLayout.rowHPadding)
                    .padding(.bottom, SettingsLayout.headerBottom)
            }
            VStack(spacing: 0) { content }
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: SettingsLayout.cardRadius, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SettingsLayout.rowHPadding)
                    .padding(.top, SettingsLayout.footerTop)
            }
        }
        .padding(.horizontal, SettingsLayout.cardHInset)
    }
}

/// カード内の 1 行。最終行以外の下に区切り線を引く。
struct SettingsRow<Content: View>: View {
    var isLast: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, SettingsLayout.rowHPadding)
                .padding(.vertical, SettingsLayout.rowVPadding)
                .frame(minHeight: SettingsLayout.rowMinHeight)
            if !isLast {
                Divider().padding(.leading, SettingsLayout.rowHPadding)
            }
        }
    }
}

/// 「項目名 + 値」の行（Form の LabeledContent 相当）。
struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(.secondary)
        }
        // ★1 行を 1 つの読み上げ単位にする（標準の `LabeledContent` と同じ）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)、\(value)")
    }
}

#Preview {
    SettingsView(proStore: ProStore())
}
