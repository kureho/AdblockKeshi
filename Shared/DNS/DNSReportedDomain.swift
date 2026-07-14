import Foundation

/// 報告された広告 URL から DNS ブロック用ドメインを取り出す純ロジック。
/// ReportedRuleBuilder.host と対称（URLComponents.host 小文字化）。
/// critical ドメイン（DNSCriticalGuard・github.io 込み）は自己リストに入れない。
enum DNSReportedDomain {

    /// URL 文字列 → 小文字 host。host が取れない/critical なら nil。
    static func extract(fromURLString urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let comps = URLComponents(string: trimmed),
              let host = comps.host, !host.isEmpty
        else { return nil }
        let lower = host.lowercased()
        guard !DNSCriticalGuard.isCritical(lower) else { return nil }   // critical は自己リストに入れない
        return lower
    }
}
