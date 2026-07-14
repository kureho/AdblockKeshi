import Foundation

/// DNS ブロック判定を集約する純関数（NetworkExtension 非依存）。
/// tunnel はこの Decision に従って「上流へ転送」か「ブロック応答を返す」だけを行う。
/// fail-open 3層: 層1=parse 不能は forward / 層2=blocklist 判定 / 層3=critical は絶対 forward。
/// spec: docs/superpowers/specs/2026-07-14-v4-freemium-dns-design.md §DNSEngine
struct DNSEngine {

    /// クエリ 1 件に対する判断。
    enum Decision: Equatable {
        /// 上流 DNS へそのまま転送する。
        case forward
        /// ブロック応答（0.0.0.0 / :: / NODATA）を即返す。
        case respond(Data)
    }

    let blocklist: DNSBlocklist

    init(blocklist: DNSBlocklist) {
        self.blocklist = blocklist
    }

    /// パース済みクエリから判断する。
    func decide(query: DNSMessage.Query) -> Decision {
        // 層3: critical はリストに載っていても絶対にブロックしない
        if DNSCriticalGuard.isCritical(query.qname) { return .forward }
        // 層2: blocklist 一致 → ブロック応答を即返す
        if blocklist.isBlocked(query.qname) {
            return .respond(DNSMessage.buildBlockResponse(for: query))
        }
        return .forward
    }

    /// raw パケットの payload（DNS メッセージ）から判断する。parse 不能は forward（層1 fail-open）。
    func decideRaw(_ data: Data) -> Decision {
        guard let query = DNSMessage.parseQuery(data) else { return .forward }
        return decide(query: query)
    }
}
