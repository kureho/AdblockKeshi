import Foundation
import NetworkExtension
import Network

/// DNS トンネル本体（ローカル VPN・split tunnel で DNS のみ捕捉）。
/// ★NetworkExtension 依存＝シミュレータでは動作しない（ビルドは通る・ランタイム検証は実機のみ）。
/// パケット判定は純関数（PacketCodec / DNSEngine / DNSBlocklist / DNSForwardingTable）に委譲し、
/// ここは I/O 配線に徹する（純関数は Task 1-12.7 / 4.0.1 hotfix で TDD 済み）。
///
/// 4.0.1 hotfix（モバイル回線 NAT64/DNS64 全断障害）:
/// - 上流 = トンネル確立「前」に snapshot したシステム DNS（キャリア DNS64 を生かす）→ Cloudflare は最後の砦
/// - watchdog = 上流無応答なら rotate → 全滅なら cancelTunnelWithError（端末のネットを死んだままにしない）
/// - 受信ループはエラーでも再武装（v4.0.0 は最初のエラーで永久停止だった）
/// - ネットワーク切替（Wi-Fi⇄モバイル）で reassert して snapshot を取り直す
final class PacketTunnelProvider: NEPacketTunnelProvider {

    private let workQueue = DispatchQueue(label: "com.kureho.adblockkeshi.tunnel")
    private var engine: DNSEngine?
    private let forwarding = DNSForwardingTable()
    private var upstreamPlan: [String] = []
    private var upstreamIndex = 0
    private var upstream: NWConnection?
    private var health: DNSHealthMonitor?
    private var pathMonitor: NWPathMonitor?
    private var pathSignature: String?
    private var isReasserting = false
    private var nextRewriteID: UInt16 = 1
    private var maintenanceTimer: DispatchSourceTimer?
    private var selfFetchTimer: DispatchSourceTimer?

    /// sentinel = RFC 2544 予約帯（198.18.0.0/15）。tunnel が DNS を吸い込むための擬似 DNS サーバ IP。
    private enum Net {
        static let sentinelV4 = "198.18.0.1"
        static let sentinelV6 = "fd00::1"
        static let tunnelV4 = "198.18.0.2"
        static let tunnelV6 = "fd00::2"
        /// システム DNS が取れない時の最後の砦（v4.0.0 まではこれが唯一の上流で、モバイル回線全断の原因だった）
        static let fallbackUpstreams = ["1.1.1.1", "2606:4700:4700::1111"]
        /// snapshot から必ず除外する自分自身のアドレス（転送ループ防止）
        static let selfAddresses: Set<String> = [sentinelV4, sentinelV6, tunnelV4, tunnelV6]
    }

    // MARK: - ライフサイクル

    override func startTunnel(options: [String: NSObject]?,
                             completionHandler: @escaping (Error?) -> Void) {
        // ① 非 Pro は起動拒否（設定アプリ VPN からの直接 ON も塞ぐ・返金 edge も起動時再検証で反映）
        let isPro = ProStateStore.sharedAppGroup()?.read().isPro ?? false
        guard isPro else {
            completionHandler(NSError(domain: NEVPNErrorDomain,
                                      code: NEVPNError.configurationInvalid.rawValue))
            return
        }

        reloadEngine()

        // ② トンネル確立「前」にシステム DNS を snapshot（確立後は resolv.conf が sentinel に置き換わる）
        rebuildUpstreamPlan()

        // ③ network settings: sentinel だけを tunnel に向ける split tunnel、DNS を全捕捉
        setTunnelNetworkSettings(makeSettings()) { [weak self] error in
            guard let self else { completionHandler(error); return }
            if let error { completionHandler(error); return }
            self.workQueue.async {
                self.activateUpstreams()
                self.startMaintenanceTimer()
                self.startPathMonitor()
            }
            self.readLoop()
            completionHandler(nil)   // bundled/App Group リストで即起動
            // 起動後に最新リストを self-fetch（成功したら reload）+ 定期更新
            self.performSelfFetch()
            self.startSelfFetchTimer()
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                            completionHandler: @escaping () -> Void) {
        maintenanceTimer?.cancel(); maintenanceTimer = nil
        selfFetchTimer?.cancel(); selfFetchTimer = nil
        pathMonitor?.cancel(); pathMonitor = nil
        upstream?.cancel(); upstream = nil
        completionHandler()
    }

    /// app からの即時 reload（sendProviderMessage）。リスト更新後の反映に使う。
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        workQueue.async { [weak self] in
            self?.reloadEngine()
            completionHandler?(nil)
        }
    }

    // MARK: - エンジン（curated ∪ self をロード）

    private func reloadEngine() {
        let curated = BlocklistStore.shared().loadDomains()
        let selfReported = DNSSelfReportStore.sharedAppGroup()?.readDomains() ?? []
        let blocklist = DNSBlocklistLoader.effectiveBlocklist(curated: curated, selfReported: selfReported)
        engine = DNSEngine(blocklist: blocklist)
    }

    // MARK: - network settings

    private func makeSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        let v4 = NEIPv4Settings(addresses: [Net.tunnelV4], subnetMasks: ["255.255.255.0"])
        v4.includedRoutes = [NEIPv4Route(destinationAddress: Net.sentinelV4, subnetMask: "255.255.255.255")]
        settings.ipv4Settings = v4

        let v6 = NEIPv6Settings(addresses: [Net.tunnelV6], networkPrefixLengths: [64])
        v6.includedRoutes = [NEIPv6Route(destinationAddress: Net.sentinelV6, networkPrefixLength: 128)]
        settings.ipv6Settings = v6

        let dns = NEDNSSettings(servers: [Net.sentinelV4, Net.sentinelV6])
        dns.matchDomains = [""]   // すべての DNS を tunnel へ
        settings.dnsSettings = dns
        return settings
    }

    // MARK: - 上流（システム DNS 優先・単一共有 UDP コネクション + rotation）

    /// システム DNS snapshot → 上流候補リスト。startTunnel（並行アクセス開始前）と reassert（workQueue 上）から呼ぶ。
    private func rebuildUpstreamPlan() {
        upstreamPlan = UpstreamPlanner.plan(systemServers: SystemDNSResolvers.snapshot(),
                                            excluding: Net.selfAddresses,
                                            fallbacks: Net.fallbackUpstreams)
    }

    /// 現在の plan で watchdog と先頭上流を（作り）直す。workQueue 上で呼ぶ。
    private func activateUpstreams() {
        health = DNSHealthMonitor(upstreamCount: upstreamPlan.count)
        startUpstream(at: 0)
    }

    /// index 番目の上流へ接続を張り替える。workQueue 上で呼ぶ。
    private func startUpstream(at index: Int) {
        upstream?.cancel()
        upstream = nil
        guard index < upstreamPlan.count else { return }   // 尽きたら watchdog の stopTunnel に任せる
        upstreamIndex = index
        let conn = NWConnection(host: NWEndpoint.Host(upstreamPlan[index]), port: 53, using: .udp)
        upstream = conn
        conn.start(queue: workQueue)
        receiveUpstream(conn)
    }

    private func receiveUpstream(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self, conn === self.upstream else { return }   // rotate/reassert 後の旧接続は破棄
            if let data, !data.isEmpty { self.handleUpstreamResponse(data) }
            if error == nil {
                self.receiveUpstream(conn)
            } else {
                // 受信エラーで再武装を止めない（v4.0.0 の脆さ修正）。1 秒おいて同じ上流を作り直す
                self.upstream = nil
                conn.cancel()
                self.workQueue.asyncAfter(deadline: .now() + 1) { [weak self] in
                    guard let self, self.upstream == nil else { return }   // rotate/reassert 済みなら不要
                    self.startUpstream(at: self.upstreamIndex)
                }
            }
        }
    }

    // MARK: - packetFlow ループ

    private func readLoop() {
        packetFlow.readPackets { [weak self] packets, _ in
            guard let self else { return }
            // engine の読み書きを直列化（self-fetch reload との競合回避）
            self.workQueue.async {
                for packet in packets { self.handleOutbound(packet) }
            }
            self.readLoop()   // 再帰でループ
        }
    }

    private func handleOutbound(_ packet: Data) {
        guard let parsed = PacketCodec.parse(packet), parsed.dstPort == 53 else { return }
        switch parsed.proto {
        case .tcp:
            // TCP:53 は fail-fast: RST を即応答（userspace TCP shim は作らない・案A）
            if let rst = PacketCodec.buildTCPRST(to: parsed) {
                writeToClient(rst, version: parsed.version)
            }
        case .udp:
            guard let engine else { return }
            switch engine.decideRaw(parsed.payload) {
            case .respond(let dnsResponse):
                writeToClient(PacketCodec.buildResponse(to: parsed, payload: dnsResponse),
                              version: parsed.version)
            case .forward:
                forwardUpstream(parsed)
            }
        }
    }

    // MARK: - 上流転送（DNS ID リライトで誤配送回避）

    private func forwardUpstream(_ request: PacketCodec.ParsedPacket) {
        var payload = [UInt8](request.payload)
        guard payload.count >= 2 else { return }
        let now = Date().timeIntervalSince1970
        health?.recordForward(now: now)   // 上流が無応答でも watchdog が検知できるよう、送信可否に関わらず記録
        let rewrittenID = allocateRewriteID()
        payload[0] = UInt8(rewrittenID >> 8)
        payload[1] = UInt8(rewrittenID & 0xff)
        forwarding.insert(rewrittenID: rewrittenID, request: request, now: now)
        upstream?.send(content: Data(payload), completion: .contentProcessed { _ in })
    }

    /// tunnel 内で未使用のリライト後 ID を採番（table にあるものは避ける）。
    private func allocateRewriteID() -> UInt16 {
        for _ in 0..<65_536 {
            let id = nextRewriteID
            nextRewriteID = nextRewriteID &+ 1
            if !forwarding.contains(rewrittenID: id) { return id }
        }
        return nextRewriteID
    }

    private func handleUpstreamResponse(_ data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return }
        health?.recordResponse(now: Date().timeIntervalSince1970)
        let rewrittenID = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        guard let request = forwarding.resolve(rewrittenID: rewrittenID) else { return }
        // 応答 DNS ID を元クライアントの ID に戻す
        let reqBytes = [UInt8](request.payload)
        guard reqBytes.count >= 2 else { return }
        var resp = bytes
        resp[0] = reqBytes[0]
        resp[1] = reqBytes[1]
        writeToClient(PacketCodec.buildResponse(to: request, payload: Data(resp)),
                      version: request.version)
    }

    // MARK: - クライアントへ書き戻し

    private func writeToClient(_ packet: Data, version: PacketCodec.IPVersion) {
        let proto = (version == .v6) ? AF_INET6 : AF_INET
        packetFlow.writePackets([packet], withProtocols: [NSNumber(value: proto)])
    }

    // MARK: - 定期整備（期限切れ掃除 5s + watchdog）

    private func startMaintenanceTimer() {
        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = Date().timeIntervalSince1970
            self.forwarding.expireAll(olderThan: now - 5)   // 応答なしは偽装せず捨てる
            self.runWatchdog(now: now)
        }
        timer.resume()
        maintenanceTimer = timer
    }

    /// watchdog フェイルセーフ: 無応答なら次の上流へ、全滅ならトンネル自動停止（素の通信に戻す）。
    private func runWatchdog(now: TimeInterval) {
        guard !isReasserting, let health else { return }
        switch health.check(now: now) {
        case .none:
            break
        case .rotate:
            health.noteRotation(now: now)
            startUpstream(at: upstreamIndex + 1)
        case .stopTunnel:
            cancelTunnelWithError(NSError(
                domain: NEVPNErrorDomain,
                code: NEVPNError.connectionFailed.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "DNS 上流が応答しないため保護を自動停止しました"]))
        }
    }

    // MARK: - ネットワーク切替（Wi-Fi⇄モバイル）で snapshot を取り直す

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in self?.handlePathUpdate(path) }
        monitor.start(queue: workQueue)
        pathMonitor = monitor
    }

    private func handlePathUpdate(_ path: Network.NWPath) {
        guard path.status == .satisfied else { return }
        // 物理インターフェイスだけで署名を作る（自分の utun の付け外しで発火しないように）
        let signature = path.availableInterfaces
            .filter { $0.type == .wifi || $0.type == .cellular || $0.type == .wiredEthernet }
            .map { "\($0.type)/\($0.name)" }
            .joined(separator: ",")
        guard let last = pathSignature else { pathSignature = signature; return }   // 初回は基準記録のみ
        guard signature != last, !signature.isEmpty else { pathSignature = signature; return }
        pathSignature = signature
        reassertForNetworkChange()
    }

    /// settings を一旦外してシステム DNS を復元 → snapshot し直し → settings 再適用 → 上流作り直し。
    private func reassertForNetworkChange() {
        guard !isReasserting else { return }
        isReasserting = true
        reasserting = true
        upstream?.cancel(); upstream = nil
        setTunnelNetworkSettings(nil) { [weak self] _ in
            guard let self else { return }
            // resolv.conf がシステム DNS に戻るまで少し待ってから snapshot する
            self.workQueue.asyncAfter(deadline: .now() + 0.5) {
                self.rebuildUpstreamPlan()
                self.setTunnelNetworkSettings(self.makeSettings()) { error in
                    self.workQueue.async {
                        defer {
                            self.reasserting = false
                            self.isReasserting = false
                        }
                        if let error {
                            self.cancelTunnelWithError(error)   // 再適用に失敗＝中途半端に握らない
                            return
                        }
                        self.activateUpstreams()
                    }
                }
            }
        }
    }

    // MARK: - リスト self-fetch（tunnel 稼働中の鮮度維持・Task 14）

    /// CDN から最新 DNS リストを取得し、更新があれば engine を作り直す（reload は workQueue で直列化）。
    private func performSelfFetch() {
        Task { [weak self] in
            guard let self else { return }
            if let updated = await DNSListUpdater.shared()?.updateIfNeeded(), updated {
                self.workQueue.async { self.reloadEngine() }
            }
        }
    }

    private func startSelfFetchTimer() {
        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(deadline: .now() + 6 * 3600, repeating: 6 * 3600)   // 6時間ごと
        timer.setEventHandler { [weak self] in self?.performSelfFetch() }
        timer.resume()
        selfFetchTimer = timer
    }
}
