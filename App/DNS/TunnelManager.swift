import Foundation
import NetworkExtension
import Observation

/// DNS トンネル（PacketTunnelExtension）を本体アプリから構成・起動・監視する。
/// NETunnelProviderManager の load/save/start をラップし、VPN 状態を publish する。
/// ★初回 saveToPreferences 時に iOS の VPN 許可プロンプトが出る（ユーザー手動・回避不可）。
@MainActor
@Observable
final class TunnelManager {

    static let tunnelBundleID = "com.kureho.adblockkeshi.tunnel"

    enum Status: Equatable {
        case off, connecting, on
        case unavailable(String)
    }

    private(set) var status: Status = .off

    #if DEBUG
    /// 撮影用（--screenshot-mode）: 実 VPN なしで「有効」表示にする。Release には存在しない。
    func forceOnForScreenshot() {
        status = .on
    }
    #endif

    @ObservationIgnored private var manager: NETunnelProviderManager?
    @ObservationIgnored private var statusObserver: NSObjectProtocol?

    /// 既存の VPN 構成を読み込む（画面表示時に呼ぶ）。
    func load() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            manager = managers.first
            observeStatus()
            updateStatus()
        } catch {
            status = .unavailable(error.localizedDescription)
        }
    }

    /// トグル ON/OFF に対応。ON で構成保存 + 起動、OFF で停止。
    func setEnabled(_ enabled: Bool) async {
        if enabled { await start() } else { stop() }
    }

    /// 稼働中の tunnel にブロックリストの再読込を要求する（停止中/未構成なら何もしない）。
    ///
    /// v4.0.3: 起動時に `dns-self.json` を削除しても、既に動いている tunnel はメモリ上の
    /// DNSBlocklist を持ち続ける。アプリ更新で extension プロセスが置き換わる前提には
    /// 依存せず、ここで明示的に reload させて即座に実害を止める。
    /// 受け側は `PacketTunnelProvider.handleAppMessage` → `reloadEngine()`。
    /// reload 対象とする稼働中ステータス。
    ///
    /// `.reasserting`（ネットワーク切替中）を含めるのが重要: この状態でも tunnel プロセスは
    /// 生きていてメモリ上に旧 DNSEngine を保持しているが、`reassertForNetworkChange()` は
    /// 上流 DNS を取り直すだけで `reloadEngine()` を呼ばない。ここで除外すると、切替中に
    /// アプリを開いたユーザーだけ dns-self.json を消しても旧リストが残り続ける。
    private static let reloadableStatuses: Set<NEVPNStatus> = [.connected, .reasserting]

    static func requestReloadIfRunning() async {
        guard let managers = try? await NETunnelProviderManager.loadAllFromPreferences(),
              let session = managers.first?.connection as? NETunnelProviderSession,
              reloadableStatuses.contains(session.status)
        else { return }
        try? session.sendProviderMessage(Data()) { _ in }
    }

    // MARK: - start / stop

    private func start() async {
        do {
            let m = manager ?? NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = Self.tunnelBundleID
            proto.serverAddress = "アプリ内広告ブロック"   // 表示用（端末内処理なので実サーバーではない）
            m.protocolConfiguration = proto
            m.localizedDescription = "アプリ内広告ブロック"
            m.isEnabled = true
            try await m.saveToPreferences()    // ★初回はここで VPN 許可プロンプト
            try await m.loadFromPreferences()  // 保存後の再読込（Apple 推奨手順）
            manager = m
            observeStatus()
            try m.connection.startVPNTunnel()
            status = .connecting
        } catch {
            status = .unavailable(error.localizedDescription)
        }
    }

    private func stop() {
        manager?.connection.stopVPNTunnel()
        status = .off
    }

    // MARK: - status 監視

    private func observeStatus() {
        guard let connection = manager?.connection else { return }
        if let statusObserver { NotificationCenter.default.removeObserver(statusObserver) }
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: connection, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateStatus() }
        }
    }

    private func updateStatus() {
        guard let connection = manager?.connection else { status = .off; return }
        switch connection.status {
        case .connected: status = .on
        case .connecting, .reasserting: status = .connecting
        case .disconnected, .disconnecting, .invalid: status = .off
        @unknown default: status = .off
        }
    }
}
