import Foundation

/// DNS ブロック判定用のドメインリスト。完全一致 + ラベル境界のサフィックス一致。
/// NetworkExtension のメモリ上限対策として maxCount で縮退する。
/// spec: docs/superpowers/specs/2026-07-14-v4-freemium-dns-design.md §DNSBlocklist
struct DNSBlocklist {

    /// NE メモリ予算を踏まえた既定上限（実機プロファイル後に調整可能な安全上限）。
    static let defaultMaxCount = 200_000

    private let blocked: Set<String>

    /// 保持しているドメイン数（縮退後）。
    var count: Int { blocked.count }

    init(domains: [String], maxCount: Int = DNSBlocklist.defaultMaxCount) {
        let capped = domains.count > maxCount ? Array(domains.prefix(maxCount)) : domains
        var set = Set<String>()
        set.reserveCapacity(capped.count)
        for d in capped {
            let n = Self.normalize(d)
            if !n.isEmpty { set.insert(n) }
        }
        self.blocked = set
    }

    /// domain がブロック対象か。完全一致またはラベル境界のサフィックス一致で true。
    func isBlocked(_ domain: String) -> Bool {
        let d = Self.normalize(domain)
        guard !d.isEmpty else { return false }
        if blocked.contains(d) { return true }
        // ラベル境界のサフィックスを順に確認（"x.doubleclick.net" → "doubleclick.net", "net"）
        var idx = d.startIndex
        while let dot = d[idx...].firstIndex(of: ".") {
            let next = d.index(after: dot)
            if blocked.contains(String(d[next...])) { return true }
            idx = next
        }
        return false
    }

    /// 小文字化 + 末尾ドット除去（DNS は case-insensitive・FQDN 末尾ドットは無視）。
    private static func normalize(_ s: String) -> String {
        var d = s.lowercased()
        if d.hasSuffix(".") { d.removeLast() }
        return d
    }
}
