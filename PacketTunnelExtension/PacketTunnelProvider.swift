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
/// - watchdog = 上流無応答なら rotate → 全滅なら cancelTunnelWithError（端末のネットを死んだままにしない）。
///   電波喪失（path unsatisfied）・サスペンド復帰の無応答は上流劣化の証拠にならないので数えない
/// - 受信ループはエラーでも再武装（v4.0.0 は最初のエラーで永久停止だった）。generation で失効管理
/// - ネットワーク切替（Wi-Fi⇄モバイル）で reassert して snapshot を取り直す。システム DNS が
///   取れないまま fallback-only で運転しない（それは v4.0.0 障害の再導入）
/// - fallback 運転中は 60 秒ごとに index 0（システム DNS）へ復帰プローブ（NAT64 網で Cloudflare は
///   「応答は返るが DNS64 合成が無い」＝watchdog では検知できない部分故障になるため）
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
    private var isPathSatisfied = true
    private var isReasserting = false
    private var pendingReassert = false
    private var isShuttingDown = false
    /// 遅延ブロック（受信ループ再武装）の失効判定。startUpstream / stopTunnel / reassert で進める。
    private var upstreamGeneration = 0
    private var lastMaintenanceTick: TimeInterval?
    private var primaryProbe: NWConnection?
    private var lastPrimaryProbeAt: TimeInterval?
    private var nextRewriteID: UInt16 = 1
    private var maintenanceTimer: DispatchSourceTimer?
    private var selfFetchTimer: DispatchSourceTimer?
    /// 時限一時停止の期限（素通し運転中のみ非 nil）。maintenance tick が期限超過で自動再開する。
    private var pauseDeadline: Date?

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
        // NEProvider の専用キューから共有状態を直接触らない（workQueue 上の I/O 経路と競合する）
        workQueue.async { [weak self] in
            guard let self else { completionHandler(); return }
            self.isShuttingDown = true
            self.upstreamGeneration &+= 1   // 予約済みの再武装ブロックを失効させる
            self.maintenanceTimer?.cancel(); self.maintenanceTimer = nil
            self.selfFetchTimer?.cancel(); self.selfFetchTimer = nil
            self.pathMonitor?.cancel(); self.pathMonitor = nil
            self.primaryProbe?.cancel(); self.primaryProbe = nil
            self.upstream?.cancel(); self.upstream = nil
            completionHandler()
        }
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
        // v4.2.0 時限一時停止: 期限内なら素通しエンジン（全ドメイン forward）で運転する。
        // トンネルは止めない＝このプロセスが生き続けるので、アプリが suspend されていても
        // maintenance tick（5秒）が期限超過を検知して確実に自動再開できる。
        if let pausedUntil = DNSPauseStore.sharedAppGroup()?.readPausedUntil() {
            pauseDeadline = pausedUntil
            engine = DNSEngine(blocklist: DNSBlocklist(domains: []))
            return
        }
        pauseDeadline = nil
        let curated = BlocklistStore.shared().loadDomains()
        // ★自己報告ファストレーン(dns-self.json)は v4.0.3 で廃止したので読まない。
        // DNS には first-party / third-party の区別が無く、「広告が消えなかったページ」を
        // 報告するとその host が名前解決できなくなっていた（= サイトが開けない・4.0.2 までの不具合）。
        // 旧版で書き込まれたファイルが端末に残っていても、ここで読まないので実害は生じない。
        let blocklist = DNSBlocklistLoader.effectiveBlocklist(curated: curated, selfReported: [])
        engine = DNSEngine(blocklist: blocklist)
    }

    /// 一時停止の状態を App Group の実体と突き合わせる（maintenance tick から毎 5 秒）。
    /// 期限切れなら自動再開し、アプリからの reload 通知を取りこぼしていたらここで engine を組み直す。
    /// ★通知（`sendProviderMessage`）は best-effort で落ちうる。それに依存したままだと
    /// 「アプリでは停止中と出ているのに DNS はブロックし続ける」「解除したのに素通しのまま」が
    /// 起きるので、実体を毎 tick 読んで回収する（誤差 ≤5 秒）。判定は DNSPauseSync（テスト済みの純ロジック）。
    /// clear() は best-effort（失敗しても readPausedUntil が期限切れ nil を返すので再開自体は成立する）。
    private func syncPauseState(now: TimeInterval) {
        let at = Date(timeIntervalSince1970: now)
        let store = DNSPauseStore.sharedAppGroup()
        switch DNSPauseSync.decide(current: pauseDeadline, stored: store?.readPausedUntil(now: at), now: at) {
        case .none:
            return
        case .resumeExpired:
            pauseDeadline = nil
            try? store?.clear()
            reloadEngine()
        case .reload:
            reloadEngine()   // reloadEngine が実体を読んで pauseDeadline を張り直す
        }
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
        lastPrimaryProbeAt = nil
        startUpstream(at: 0)
    }

    /// index 番目（範囲外はラップ）の上流へ接続を張り替える。workQueue 上で呼ぶ。
    /// ラップしないと「応答実績で rotation 予算が戻ったのに index は末尾のまま」の状態で
    /// 範囲外 no-op → 上流ゼロで DNS を握る窓ができる。全滅時の停止は watchdog の予算が保証する。
    private func startUpstream(at index: Int) {
        upstreamGeneration &+= 1
        upstream?.cancel()
        upstream = nil
        guard !upstreamPlan.isEmpty else { return }   // fallback 定数があるため実際には空にならない（防御）
        upstreamIndex = index % upstreamPlan.count
        let conn = NWConnection(host: NWEndpoint.Host(upstreamPlan[upstreamIndex]), port: 53, using: .udp)
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
                // 受信エラーで再武装を止めない（v4.0.0 の脆さ修正）。1 秒おいて同じ上流を作り直す。
                // generation が進んでいたら（rotate / reassert / stopTunnel 後）復活させない
                self.upstream = nil
                conn.cancel()
                let generation = self.upstreamGeneration
                self.workQueue.asyncAfter(deadline: .now() + 1) { [weak self] in
                    guard let self, !self.isShuttingDown,
                          self.upstreamGeneration == generation, self.upstream == nil else { return }
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
        let rewrittenID = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        guard let request = forwarding.resolve(rewrittenID: rewrittenID) else { return }
        // resolve 成功＝クライアントに実際に届く応答だけを健全性の証拠にする
        // （期限切れ・未知 ID の応答で watchdog を回復させると、実利用はタイムアウトなのに rotate しない）
        health?.recordResponse(now: Date().timeIntervalSince1970)
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
            // サスペンド復帰: 止まっていた実時間中の無応答は上流劣化の証拠にならない → 白紙化
            if let last = self.lastMaintenanceTick, now - last > 30 {
                self.health?.reset()
            }
            self.lastMaintenanceTick = now
            self.forwarding.expireAll(olderThan: now - 5)   // 応答なしは偽装せず捨てる
            self.syncPauseState(now: now)                   // 時限一時停止の自動再開 + 取りこぼし回収（誤差 ≤5 秒）
            self.runWatchdog(now: now)
            self.runPrimaryRetryProbe(now: now)
        }
        timer.resume()
        maintenanceTimer = timer
    }

    /// watchdog フェイルセーフ: 無応答なら次の上流へ、全滅ならトンネル自動停止（素の通信に戻す）。
    private func runWatchdog(now: TimeInterval) {
        // 電波喪失（path unsatisfied）中の無応答は上流のせいではない → 判定しない
        guard !isReasserting, !isShuttingDown, isPathSatisfied, let health else { return }
        switch health.check(now: now) {
        case .none:
            break
        case .rotate:
            health.noteRotation(now: now)
            startUpstream(at: upstreamIndex + 1)
        case .stopTunnel:
            isShuttingDown = true   // 以後の watchdog 再発火・再武装を止める（cancel は一度きり）
            cancelTunnelWithError(NSError(
                domain: NEVPNErrorDomain,
                code: NEVPNError.connectionFailed.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "DNS 上流が応答しないため保護を自動停止しました"]))
        }
    }

    // MARK: - fallback 固定化からの自動復帰（index 0 = システム DNS への復帰プローブ）

    /// NAT64 網の Cloudflare は「応答は返るが DNS64 合成が無い」＝watchdog（応答の有無しか見ない）では
    /// 検知できない部分故障になる。非 primary 運転中は 60 秒ごとに index 0 へ別接続でプローブを打ち、
    /// 応答が返れば primary に戻す。本線 upstream は触らないので実トラフィックは劣化しない。
    private func runPrimaryRetryProbe(now: TimeInterval) {
        guard !isReasserting, !isShuttingDown, isPathSatisfied,
              upstreamIndex > 0, !upstreamPlan.isEmpty else {
            primaryProbe?.cancel(); primaryProbe = nil
            lastPrimaryProbeAt = nil
            return
        }
        guard let last = lastPrimaryProbeAt else {
            lastPrimaryProbeAt = now   // rotate 直後の即プローブはフラッピングの元 → 初回は 60 秒待つ
            return
        }
        guard now - last >= 60 else { return }
        lastPrimaryProbeAt = now
        primaryProbe?.cancel()
        let conn = NWConnection(host: NWEndpoint.Host(upstreamPlan[0]), port: 53, using: .udp)
        primaryProbe = conn
        conn.start(queue: workQueue)
        conn.receiveMessage { [weak self] data, _, _, _ in
            guard let self, conn === self.primaryProbe else { return }
            self.primaryProbe = nil
            conn.cancel()
            guard !self.isShuttingDown, !self.isReasserting, self.upstreamIndex > 0,
                  let data, !data.isEmpty else { return }
            // SERVFAIL でも応答が返る＝到達性は回復している → primary へ戻す（新しい上流に新しい window）
            self.health?.reset()
            self.startUpstream(at: 0)
        }
        conn.send(content: Self.probeQuery, completion: .contentProcessed { _ in })
    }

    /// プローブ用の固定 DNS クエリ（example.com A IN・RD=1）。応答内容は見ない＝到達性だけを確認する。
    private static let probeQuery: Data = {
        var bytes: [UInt8] = [0x4B, 0x48, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        bytes += [0x07] + Array("example".utf8) + [0x03] + Array("com".utf8) + [0x00]
        bytes += [0x00, 0x01, 0x00, 0x01]
        return Data(bytes)
    }()

    // MARK: - ネットワーク切替（Wi-Fi⇄モバイル）で snapshot を取り直す

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in self?.handlePathUpdate(path) }
        monitor.start(queue: workQueue)
        pathMonitor = monitor
    }

    private func handlePathUpdate(_ path: Network.NWPath) {
        let satisfied = (path.status == .satisfied)
        if isPathSatisfied != satisfied {
            isPathSatisfied = satisfied
            // 電波喪失区間（とその復帰）をまたいだ無応答は上流劣化の証拠にならない → 白紙化。
            // 喪失中は runWatchdog 自体も止まるので、誤 rotate / 誤 stopTunnel が構造的に起きない
            health?.reset()
        }
        guard satisfied else { return }
        // 物理インターフェイスだけで署名を作る（自分の utun の付け外しで発火しないように）
        let signature = path.availableInterfaces
            .filter { $0.type == .wifi || $0.type == .cellular || $0.type == .wiredEthernet }
            .map { "\($0.type)/\($0.name)" }
            .joined(separator: ",")
        guard let last = pathSignature else { pathSignature = signature; return }   // 初回は基準記録のみ
        guard signature != last, !signature.isEmpty else { pathSignature = signature; return }
        pathSignature = signature
        if isReasserting {
            pendingReassert = true   // reassert 中に来た切替は握りつぶさず、完了後にやり直す
        } else {
            reassertForNetworkChange()
        }
    }

    /// settings を一旦外してシステム DNS を復元 → snapshot し直し → settings 再適用 → 上流作り直し。
    private func reassertForNetworkChange() {
        guard !isReasserting, !isShuttingDown else { return }
        isReasserting = true
        reasserting = true
        upstreamGeneration &+= 1   // 予約済みの再武装ブロックを失効させる
        upstream?.cancel(); upstream = nil
        primaryProbe?.cancel(); primaryProbe = nil
        setTunnelNetworkSettings(nil) { [weak self] error in
            guard let self else { return }
            self.workQueue.async {
                // stopTunnel（手動 OFF）後に遅延完了した場合は何もしない（cancel の二重発火防止）
                guard !self.isShuttingDown else { return }
                if error != nil {
                    // settings を外せない＝resolv.conf が sentinel のままで snapshot が汚染される。
                    // fallback 直行（v4.0.0 障害の再導入）はせず、中途半端に握らず自動停止する
                    self.finishReassert(cancelWith: NSError(
                        domain: NEVPNErrorDomain,
                        code: NEVPNError.connectionFailed.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: "ネットワーク切替の再設定に失敗したため保護を自動停止しました"]))
                    return
                }
                self.resnapshotThenReapply(attemptsLeft: ReassertRetryPolicy.maxAttempts)
            }
        }
    }

    /// resolv.conf がシステム DNS に戻るまで ReassertRetryPolicy の間隔で snapshot をリトライ（予算 30 秒）。
    /// Wi-Fi join 直後は DHCP が DNS を configure するまで数秒〜十数秒かかるため、予算が短いと
    /// 日常の Wi-Fi 切替で cancel（トグル勝手 OFF）になる（2026-07-29 実機で実測 → v4.0.1 で延長）。
    /// 取れないまま fallback-only で運転すると NAT64 網で v4.0.0 障害が再発するため、諦める時は停止する。
    private func resnapshotThenReapply(attemptsLeft: Int) {
        workQueue.asyncAfter(deadline: .now() + ReassertRetryPolicy.interval) { [weak self] in
            guard let self, !self.isShuttingDown else { return }
            let snapshot = SystemDNSResolvers.snapshot()
            let systemOnly = UpstreamPlanner.plan(systemServers: snapshot,
                                                  excluding: Net.selfAddresses, fallbacks: [])
            if systemOnly.isEmpty {
                if attemptsLeft > 1 {
                    self.resnapshotThenReapply(attemptsLeft: attemptsLeft - 1)
                } else {
                    self.finishReassert(cancelWith: NSError(
                        domain: NEVPNErrorDomain,
                        code: NEVPNError.connectionFailed.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: "ネットワーク切替後に回線の DNS を取得できないため保護を自動停止しました"]))
                }
                return
            }
            self.upstreamPlan = UpstreamPlanner.plan(systemServers: snapshot,
                                                     excluding: Net.selfAddresses,
                                                     fallbacks: Net.fallbackUpstreams)
            self.setTunnelNetworkSettings(self.makeSettings()) { error in
                self.workQueue.async {
                    // stopTunnel（手動 OFF）後に遅延完了した場合、上流を再生成してはいけない
                    guard !self.isShuttingDown else { return }
                    if let error {
                        self.finishReassert(cancelWith: error)   // 再適用に失敗＝中途半端に握らない
                        return
                    }
                    self.reasserting = false
                    self.isReasserting = false
                    self.activateUpstreams()
                    if self.pendingReassert {   // reassert 中に来ていた次の切替をやり直す
                        self.pendingReassert = false
                        self.reassertForNetworkChange()
                    }
                }
            }
        }
    }

    private func finishReassert(cancelWith error: Error) {
        reasserting = false
        isReasserting = false
        pendingReassert = false
        isShuttingDown = true
        cancelTunnelWithError(error)
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
