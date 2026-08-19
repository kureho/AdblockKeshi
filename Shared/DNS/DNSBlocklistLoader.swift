import Foundation

/// tunnel が使う実効ブロックリストを組み立てる純ロジック。
/// 供給源は curated（bundle 同梱 / CDN self-fetch）のみ。
///
/// ★v4.0.3 以降、自己報告（`dns-self.json`）は union しない。
/// DNS には first-party / third-party の区別が無いため、報告した host を自分の端末で
/// ブロックすると **そのサイト自体が名前解決できなくなる**（報告先サイトが開けなくなる実害）。
/// `PacketTunnelProvider` は `selfReported: []` を渡す。引数は union ロジックの
/// テスト可能性のために残してあるだけで、本番から非空が入る経路は存在しない。
enum DNSBlocklistLoader {

    /// curated と（現在は常に空の）self-reported を union して DNSBlocklist を作る。
    static func effectiveBlocklist(
        curated: [String],
        selfReported: [String],
        maxCount: Int = DNSBlocklist.defaultMaxCount
    ) -> DNSBlocklist {
        return DNSBlocklist(domains: curated + selfReported, maxCount: maxCount)
    }
}
