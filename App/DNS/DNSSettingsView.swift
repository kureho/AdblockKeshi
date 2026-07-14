import SwiftUI

/// アプリ内広告ブロック（DNS）の設定画面。
/// 非 Pro は Paywall、Pro はワンタップトグル + 状態 + 限界明記（他VPN排他・再起動後は手動ON・
/// YouTube等は不可・上流 Cloudflare・端末内処理）。
/// ★トグルの実 tunnel 起動は Chunk 3（NETunnelProviderManager・実機のみ）で配線する。
struct DNSSettingsView: View {
    let store: ProStore

    // Chunk 3 で TunnelManager の status に置き換える（実機で tunnel を起動/停止）。
    @State private var isBlockingEnabled = false

    var body: some View {
        Group {
            if store.isPro {
                proContent
            } else {
                PaywallView(store: store)
            }
        }
        .navigationTitle("アプリ内広告ブロック")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Pro（有効化トグル + 説明）

    private var proContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                toggleCard
                explanationCard
                restoreFooter
            }
            .padding(20)
        }
    }

    private var toggleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $isBlockingEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("アプリ内広告ブロック")
                        .font(.system(size: 16, weight: .bold))
                    Text(isBlockingEnabled ? "この端末で有効です" : "オンにすると端末内の DNS で広告を抑えます")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Color.accentColor)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("この機能について")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.secondary)
            InfoRow(icon: "lock.shield", iconColor: .accentColor,
                    text: "判定もクエリも端末内。外部サーバーは経由しません")
            InfoRow(icon: "network", iconColor: .blue,
                    text: "名前解決先は Cloudflare（1.1.1.1）に変わります")
            InfoRow(icon: "personalhotspot", iconColor: .purple,
                    text: "VPN 表示になります（他の VPN とは同時に使えません）")
            InfoRow(icon: "arrow.clockwise", iconColor: .orange,
                    text: "端末を再起動した後は、もう一度オンにしてください")
            InfoRow(icon: "exclamationmark.triangle", iconColor: .gray,
                    text: "YouTube・X・Instagram・一部ゲームの広告は抑えられません")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    /// Pro 状態でも購入/復元 UI に到達可能（814236 reject 対策・復元導線を常設）。
    private var restoreFooter: some View {
        Button("購入を復元") { Task { await store.restore() } }
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
    }
}
