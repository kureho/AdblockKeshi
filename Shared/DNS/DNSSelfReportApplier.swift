import Foundation

/// 報告された広告 URL を DNS 自己ファストレーンへ反映する（テスト可能な薄いロジック）。
/// SelfReportApplier（Content Blocker 側）から呼ばれ、同じ報告で DNS ブロックも即増やす。
struct DNSSelfReportApplier {
    let store: DNSSelfReportStore

    /// 報告 URL からドメインを取り出して自己リストに追記する。host なし/critical は無視。
    func apply(reportedURL: URL) {
        guard let domain = DNSReportedDomain.extract(fromURLString: reportedURL.absoluteString) else { return }
        try? store.appendDomain(domain)
    }
}
