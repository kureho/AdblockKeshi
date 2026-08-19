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

    /// 時限一時停止の期限（nil = 停止していない）。UI 表示用に store の値をミラーする。
    private(set) var pausedUntil: Date?

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
            refreshPauseState()
        } catch {
            status = .unavailable(error.localizedDescription)
        }
    }

    // MARK: - 時限一時停止（v4.2.0・自動再開つき）

    /// DNS 保護を一時停止する。トンネルは止めず、extension が素通しエンジンに切り替える
    /// （stopTunnel 方式はアプリ suspend 中に再開経路が消え「戻し忘れ」を再生産するため不採用）。
    /// 自動再開は extension 側 maintenance tick（5 秒間隔）が保証する。
    func pauseProtection(for duration: DNSPauseStore.Duration, now: Date = Date()) async {
        guard let store = DNSPauseStore.sharedAppGroup() else { return }
        let until = now.addingTimeInterval(duration.rawValue)
        do {
            try store.pause(until: until)
        } catch {
            return   // 書けなければ何も変わっていない（保護は生きたまま）
        }
        pausedUntil = until
        await Self.requestReloadIfRunning()
    }

    /// 一時停止を今すぐ解除して保護を再開する。
    func resumeProtection() async {
        try? DNSPauseStore.sharedAppGroup()?.clear()
        pausedUntil = nil
        await Self.requestReloadIfRunning()
    }

    /// store の現在値を UI 状態へ反映する（期限切れは nil に落ちる）。
    func refreshPauseState(now: Date = Date()) {
        pausedUntil = DNSPauseStore.sharedAppGroup()?.readPausedUntil(now: now)
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
    /// 判定基準は「extension プロセスがメモリ上に DNSEngine を保持している可能性があるか」。
    /// engine を持っているのに reload を送らないと、`dns-self.json` を消しても旧リストで
    /// 報告 host をブロックし続ける窓が残る。
    ///
    /// - `.connecting`: `startTunnel` は**最初に** `reloadEngine()` を呼ぶ（接続確立を待たない）。
    ///   したがってこの時点で既に旧 `dns-self.json` を読んだ engine が存在する。
    /// - `.connected`: 通常の稼働中。
    /// - `.reasserting`: ネットワーク切替中。`reassertForNetworkChange()` は上流 DNS を
    ///   取り直すだけで `reloadEngine()` を呼ばないため、放置すると自力で復帰しない。
    ///
    /// `.disconnecting` を含めないのは、間もなく engine ごと破棄されるため（自然解消する）。
    /// `.invalid` / `.disconnected` は engine が存在しない。
    private static let reloadableStatuses: Set<NEVPNStatus> = [.connecting, .connected, .reasserting]

    static func requestReloadIfRunning() async {
        guard let managers = try? await NETunnelProviderManager.loadAllFromPreferences(),
              let session = managers.first?.connection as? NETunnelProviderSession,
              reloadableStatuses.contains(session.status)
        else { return }
        // best-effort。ここが落ちても extension の maintenance tick（5 秒）が App Group の
        // 実体と突き合わせて拾い直す（DNSPauseSync）ので、停止・解除が迷子にならない。
        try? session.sendProviderMessage(Data()) { _ in }
    }

    // MARK: - 診断用（報告に添える dns_enabled）

    /// その status のとき **実際に DNS 保護が効いていた**か。
    /// 報告の診断値は「Pro を買ったか」ではなく「そのとき守られていたか」でなければ
    /// 「保護 ON なのに広告が出た」と「そもそも保護 OFF」を切り分けられない。
    ///
    /// ★上の `reloadableStatuses` と**わざと違う集合**にしてある。あちらの問いは
    /// 「extension がメモリ上に DNSEngine を持っているか」で、こちらは
    /// 「その瞬間 DNS がブロックエンジンを通っていたか」。揃えてはいけない。
    ///
    /// - `.connected`: 通常の稼働中。**これだけが保護中**。
    /// - `.reasserting`: `PacketTunnelProvider.reassertForNetworkChange()` が
    ///   `setTunnelNetworkSettings(nil)` で設定を一旦外し、システム DNS を復元している最中。
    ///   DNS はブロックエンジンを通らないので保護中ではない。ここを true にすると、
    ///   切替中に見た広告が「保護 ON なのに取りこぼした」と誤分類される。
    /// - `.connecting`: まだ経路が確立しておらず保護は始まっていない。
    nonisolated static func isProtecting(_ status: NEVPNStatus) -> Bool {
        status == .connected
    }

    /// 現在 DNS 保護が動いているか。構成を読めなければ nil（＝診断不能。false と区別する）。
    /// 未構成（一度も ON にしていない）は「動いていない」が確定するので false。
    nonisolated static func currentlyProtecting() async -> Bool? {
        guard let managers = try? await NETunnelProviderManager.loadAllFromPreferences()
        else { return nil }
        guard let connection = managers.first?.connection else { return false }
        return isProtecting(connection.status)
    }

    // MARK: - start / stop

    private func start() async {
        // 手動 ON = 守る意思の表明。残っている一時停止は解除してから起動する
        // （停止期限が残ったまま起動すると「ON にしたのに効かない」に見える）。
        try? DNSPauseStore.sharedAppGroup()?.clear()
        pausedUntil = nil
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
        // 手動 OFF 後の一時停止は無意味（保護自体が止まる）ので残さない。
        try? DNSPauseStore.sharedAppGroup()?.clear()
        pausedUntil = nil
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
