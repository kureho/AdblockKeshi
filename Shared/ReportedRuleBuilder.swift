import Foundation

/// Safari Content Blocker のルール1件（host-block）。
/// JSON キーは Safari が要求する `url-filter` / `type` に一致させる。
struct ContentBlockerRule: Codable, Equatable {
    struct Trigger: Codable, Equatable {
        let urlFilter: String
        enum CodingKeys: String, CodingKey { case urlFilter = "url-filter" }
    }
    struct Action: Codable, Equatable {
        let type: String
    }
    let trigger: Trigger
    let action: Action
}

/// 報告された広告URLから host-block ルールを生成する純粋ロジック。
/// 生成形式はサーバ側 reported-rules / 標準フィルタと同一:
///   `^[^:]+://+([^:/]+\.)?<escaped-host>[/:]`
/// （任意のサブドメインを含む host 全体をブロック）。
enum ReportedRuleBuilder {

    static func blockRule(forURL urlString: String) -> ContentBlockerRule? {
        guard let host = host(from: urlString) else { return nil }
        let escaped = host.replacingOccurrences(of: ".", with: #"\."#)
        let filter = #"^[^:]+://+([^:/]+\.)?"# + escaped + "[/:]"
        return ContentBlockerRule(
            trigger: .init(urlFilter: filter),
            action: .init(type: "block")
        )
    }

    /// URL 文字列から host を取り出す。スキーム無し等で host が取れなければ nil。
    private static func host(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let comps = URLComponents(string: trimmed),
              let host = comps.host,
              !host.isEmpty
        else { return nil }
        return host.lowercased()
    }
}
