import Foundation

/// 報告反映 Content Blocker（popunder L1+L2 + reported）へ reported を統合する際の安全フィルタ。
///
/// popunder L2 の `ignore-previous-rules` は対象サイトで特定ドメイン（プレーヤー等）を許可する。
/// reported は ipr の後ろに置かれるため、もし reported がその許可ドメインを block すると、
/// その2サイトで再 block され L2 が温存したプレーヤーを壊す。これを防ぐため、L2 ipr が許可する
/// ドメイン（およびそのサブドメイン）に一致する reported rule を **必須で除外**する。
/// 設計: docs/architecture/report-rule-reallocation-audit.md。
enum PopunderReportedFilter {
    /// host-block 形式 `^[^:]+://+([^:/]+\.)?<escaped-host>[/:]` の url-filter から host を取り出す。
    /// 形式が一致しなければ nil（`.*` 等の広域 block は host を持たない）。
    static func host(fromURLFilter urlFilter: String) -> String? {
        let prefix = #"^[^:]+://+([^:/]+\.)?"#
        let suffix = "[/:]"
        guard urlFilter.hasPrefix(prefix), urlFilter.hasSuffix(suffix) else { return nil }
        let core = String(urlFilter.dropFirst(prefix.count).dropLast(suffix.count))
        let host = core.replacingOccurrences(of: #"\."#, with: ".")
        return host.isEmpty ? nil : host
    }

    /// popunder L2 の `ignore-previous-rules` ルール群が許可するドメイン集合（host 抽出）。
    static func l2AllowedDomains(popunderRules: [ContentBlockerRule]) -> Set<String> {
        var domains = Set<String>()
        for rule in popunderRules where rule.action.type == "ignore-previous-rules" {
            if let h = host(fromURLFilter: rule.trigger.urlFilter) {
                domains.insert(h)
            }
        }
        return domains
    }

    /// reported から、L2 許可ドメイン（およびそのサブドメイン）に一致するものを除外する。
    static func excludingL2Allowed(_ reported: [ContentBlockerRule],
                                   allowed: Set<String>) -> [ContentBlockerRule] {
        guard !allowed.isEmpty else { return reported }
        return reported.filter { rule in
            guard let h = host(fromURLFilter: rule.trigger.urlFilter) else { return true }
            let isAllowed = allowed.contains(h) || allowed.contains(where: { h.hasSuffix("." + $0) })
            return !isAllowed
        }
    }
}
