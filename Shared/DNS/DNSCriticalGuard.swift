import Foundation

/// DNS ブロックの最終安全弁（fail-open 層3）。
/// 決済/銀行/大手/政府 等の重要ドメインは、リストに載っていても絶対にブロックしない。
/// レポート fastlane の `CriticalDomainGuard` を継承し、DNS 経路固有の保護先を足す。
/// spec: docs/superpowers/specs/2026-07-14-v4-freemium-dns-design.md §fail-open 層3 / self-fetch 保護
enum DNSCriticalGuard {

    /// DNS 経路でのみ守る追加ドメイン。
    /// `github.io` = 自己更新リストの配信元（GitHub Pages）。ここをブロックすると
    /// リスト更新の自己生存経路（self-fetch）が断たれるため必ず素通しする。
    static let dnsSpecific: Set<String> = ["github.io"]

    /// レポート fastlane の critical リスト + DNS 固有の追加。単一ソースを継承して二重管理を避ける。
    static let criticalDomains: Set<String> = CriticalDomainGuard.criticalDomains.union(dnsSpecific)

    static func isCritical(_ host: String) -> Bool {
        let domain = host.lowercased()
        if criticalDomains.contains(domain) { return true }
        for critical in criticalDomains where domain.hasSuffix("." + critical) {
            return true
        }
        return false
    }
}
