import SwiftUI

/// アプリ内広告ブロック（DNS）の設定画面。
/// 非 Pro は Paywall、Pro はワンタップトグル + 状態 + 限界明記（他VPN排他・再起動後は手動ON・
/// YouTube等は不可・上流は通常お使いの回線の DNS（取得できない場合のみ代替 DNS）・判定は端末内）。
/// ★トグルの実 tunnel 起動は Chunk 3（NETunnelProviderManager・実機のみ）で配線する。
struct DNSSettingsView: View {
    let store: ProStore

    @State private var tunnel = TunnelManager()

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
        .task {
            #if DEBUG
            // 撮影モード時は実 VPN を読まず「有効」表示に固定（sim には NE が無く IPC failed になるため）。
            if ScreenshotMode.isActive {
                tunnel.forceOnForScreenshot()
                return
            }
            #endif
            // ゲート判定前に Pro 権利を最新化（既存購入・grandfather を反映。P1 対策）。
            // DEBUG 強制 Pro 時は StoreKit 参照が不要（sim ではサインイン要求が出るため）まとめてスキップ。
            if !ProStore.resolveDebugForcePro() {
                await store.refreshEntitlements()
                await store.refreshGrandfatherFromAppTransaction()
            }
            await tunnel.load()
        }
    }

    // MARK: - Pro（有効化トグル + 説明）

    private var proContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                toggleCard
                if tunnel.status == .on || tunnel.pausedUntil != nil {
                    pauseCard
                }
                explanationCard
                restoreFooter
            }
            .padding(20)
        }
    }

    /// トグルは tunnel の status に連動（connecting/on を「オン」扱い）。
    private var isEnabledBinding: Binding<Bool> {
        Binding(
            get: { tunnel.status == .on || tunnel.status == .connecting },
            set: { on in Task { await tunnel.setEnabled(on) } }
        )
    }

    private var statusSubtitle: String {
        switch tunnel.status {
        case .on: return "この端末で有効です"
        case .connecting: return "接続中…"
        case .off: return "オンにすると端末内の DNS で広告を抑えます"
        case .unavailable(let msg): return "有効化できませんでした: \(msg)"
        }
    }

    private var toggleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: isEnabledBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("アプリ内広告ブロック")
                        .font(.system(size: 16, weight: .bold))
                    Text(statusSubtitle)
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

    /// v4.2.0: 時限一時停止（自動再開つき）。サイトや他アプリの不調時に「全 OFF → 戻し忘れ」を防ぐ。
    private var pauseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("一時停止")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.secondary)
            if let until = tunnel.pausedUntil {
                HStack(spacing: 8) {
                    Image(systemName: "pause.circle.fill")
                        .foregroundStyle(.orange)
                    Text("停止中 · \(until.formatted(date: .omitted, time: .shortened)) に自動で再開します")
                        .font(.footnote)
                }
                Button {
                    Task { await tunnel.resumeProtection() }
                } label: {
                    Text("今すぐ再開")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            } else {
                HStack(spacing: 10) {
                    pauseButton("15分", duration: .fifteenMinutes)
                    pauseButton("1時間", duration: .oneHour)
                }
                Text("サイトやアプリの調子が悪いときに。時間が来ると自動で保護を再開します")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    private func pauseButton(_ label: String, duration: DNSPauseStore.Duration) -> some View {
        Button {
            Task { await tunnel.pauseProtection(for: duration) }
        } label: {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("この機能について")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.secondary)
            InfoRow(icon: "lock.shield", iconColor: .accentColor,
                    text: "広告の判定は端末内。閲覧履歴を収集・送信しません")
            InfoRow(icon: "network", iconColor: .blue,
                    text: "名前解決は通常お使いの回線の DNS を利用します（取得できない場合のみ代替 DNS）")
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
