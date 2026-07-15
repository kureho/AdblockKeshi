import Foundation
import NetworkExtension
import Network

/// DNS トンネル本体（ローカル VPN・split tunnel で DNS のみ捕捉）。
/// ★NetworkExtension 依存＝シミュレータでは動作しない（ビルドは通る・ランタイム検証は実機のみ）。
/// パケット判定は純関数（PacketCodec / DNSEngine / DNSBlocklist / DNSForwardingTable）に委譲し、
/// ここは I/O 配線に徹する（純関数は Task 1-12.7 で TDD 済み）。
final class PacketTunnelProvider: NEPacketTunnelProvider {

    private let workQueue = DispatchQueue(label: "com.kureho.adblockkeshi.tunnel")
    private var engine: DNSEngine?
    private let forwarding = DNSForwardingTable()
    private var upstreamV4: NWConnection?
    private var upstreamV6: NWConnection?
    private var nextRewriteID: UInt16 = 1
    private var expiryTimer: DispatchSourceTimer?
    private var selfFetchTimer: DispatchSourceTimer?

    /// sentinel = RFC 2544 予約帯（198.18.0.0/15）。tunnel が DNS を吸い込むための擬似 DNS サーバ IP。
    private enum Net {
        static let sentinelV4 = "198.18.0.1"
        static let sentinelV6 = "fd00::1"
        static let tunnelV4 = "198.18.0.2"
        static let tunnelV6 = "fd00::2"
        static let upstreamV4 = "1.1.1.1"
        static let upstreamV6 = "2606:4700:4700::1111"
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

        // ② network settings: sentinel だけを tunnel に向ける split tunnel、DNS を全捕捉
        setTunnelNetworkSettings(makeSettings()) { [weak self] error in
            guard let self else { completionHandler(error); return }
            if let error { completionHandler(error); return }
            self.startUpstreams()
            self.startExpiryTimer()
            self.readLoop()
            completionHandler(nil)   // bundled/App Group リストで即起動
            // 起動後に最新リストを self-fetch（成功したら reload）+ 定期更新
            self.performSelfFetch()
            self.startSelfFetchTimer()
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                            completionHandler: @escaping () -> Void) {
        expiryTimer?.cancel(); expiryTimer = nil
        selfFetchTimer?.cancel(); selfFetchTimer = nil
        upstreamV4?.cancel(); upstreamV6?.cancel()
        upstreamV4 = nil; upstreamV6 = nil
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

    // MARK: - 上流（1.1.1.1 / v6・共有 UDP コネクション）

    private func startUpstreams() {
        upstreamV4 = makeUpstream(host: Net.upstreamV4)
        upstreamV6 = makeUpstream(host: Net.upstreamV6)
    }

    private func makeUpstream(host: String) -> NWConnection {
        let conn = NWConnection(host: NWEndpoint.Host(host), port: 53, using: .udp)
        conn.start(queue: workQueue)
        receiveUpstream(conn)
        return conn
    }

    private func receiveUpstream(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            if let data, !data.isEmpty { self?.handleUpstreamResponse(data) }
            if error == nil { self?.receiveUpstream(conn) }
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
        let rewrittenID = allocateRewriteID()
        payload[0] = UInt8(rewrittenID >> 8)
        payload[1] = UInt8(rewrittenID & 0xff)
        forwarding.insert(rewrittenID: rewrittenID, request: request, now: Date().timeIntervalSince1970)
        let conn = (request.version == .v6) ? upstreamV6 : upstreamV4
        conn?.send(content: Data(payload), completion: .contentProcessed { _ in })
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

    // MARK: - 期限切れ掃除（応答なしは偽装せず捨てる・5s）

    private func startExpiryTimer() {
        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            self?.forwarding.expireAll(olderThan: Date().timeIntervalSince1970 - 5)
        }
        timer.resume()
        expiryTimer = timer
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
