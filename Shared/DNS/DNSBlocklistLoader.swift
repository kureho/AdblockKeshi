import Foundation

/// tunnel が使う実効ブロックリストを組み立てる純ロジック。
/// curated（bundle 同梱 / CDN self-fetch）∪ self（あなたの報告・DNSSelfReportStore）を union する。
/// これで「あなたの報告で他アプリの広告ブロックも即増える」が成立する。
enum DNSBlocklistLoader {

    /// curated と self-reported を union して DNSBlocklist を作る。
    static func effectiveBlocklist(
        curated: [String],
        selfReported: [String],
        maxCount: Int = DNSBlocklist.defaultMaxCount
    ) -> DNSBlocklist {
        return DNSBlocklist(domains: curated + selfReported, maxCount: maxCount)
    }
}
