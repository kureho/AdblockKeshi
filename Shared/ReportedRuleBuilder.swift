import Foundation

/// Safari Content Blocker のルール1件。
/// JSON キーは Safari が要求する `url-filter` / `if-domain` / `resource-type` /
/// `load-type` / `type` / `selector` に一致させる。
/// 報告 host-block（action=block）に加え、サーバ昇格の cosmetic（css-display-none + selector）も
/// 破壊せず round-trip できるよう、関連フィールドを optional で保持する。
struct ContentBlockerRule: Codable, Equatable, Hashable {
    struct Trigger: Codable, Equatable, Hashable {
        let urlFilter: String
        var ifDomain: [String]?
        var unlessDomain: [String]?
        var resourceType: [String]?
        var loadType: [String]?

        init(urlFilter: String,
             ifDomain: [String]? = nil,
             unlessDomain: [String]? = nil,
             resourceType: [String]? = nil,
             loadType: [String]? = nil) {
            self.urlFilter = urlFilter
            self.ifDomain = ifDomain
            self.unlessDomain = unlessDomain
            self.resourceType = resourceType
            self.loadType = loadType
        }

        enum CodingKeys: String, CodingKey {
            case urlFilter = "url-filter"
            case ifDomain = "if-domain"
            case unlessDomain = "unless-domain"
            case resourceType = "resource-type"
            case loadType = "load-type"
        }
    }
    struct Action: Codable, Equatable, Hashable {
        let type: String
        var selector: String?

        init(type: String, selector: String? = nil) {
            self.type = type
            self.selector = selector
        }
    }
    let trigger: Trigger
    let action: Action
}

/// 報告された広告URLから host-block ルールを生成する純粋ロジック。
/// 生成形式はサーバ側 reported-rules / 標準フィルタと同一:
///   `^[^:]+://+([^:/]+\.)?<escaped-host>[/:]`
/// （任意のサブドメインを含む host 全体をブロック）。
enum ReportedRuleBuilder {

    /// 報告 host を block する resource-type 群。
    /// `document` を**意図的に除外**して top-level ページ自体の遮断を防ぐ
    /// （訪問中サイトを報告しても、そのページのドキュメントは落ちない）。
    /// 広告として埋まる image/script/media/popup 等は引き続きブロックする。
    private static let blockableResourceTypes =
        ["image", "style-sheet", "script", "font", "raw", "svg-document", "media", "popup"]

    static func blockRule(forURL urlString: String) -> ContentBlockerRule? {
        guard let host = host(from: urlString) else { return nil }
        // 安全弁: 決済/銀行/大手など重要ドメインは誤報告でもブロックしない
        guard !CriticalDomainGuard.isCritical(host) else { return nil }
        let escaped = host.replacingOccurrences(of: ".", with: #"\."#)
        let filter = #"^[^:]+://+([^:/]+\.)?"# + escaped + "[/:]"
        // load-type:third-party 限定 + document 除外 = 訪問中サイトを first-party で絶対に遮断しない。
        // その host が他サイトで third-party 広告として現れる時だけブロックされる。
        return ContentBlockerRule(
            trigger: .init(urlFilter: filter,
                           resourceType: blockableResourceTypes,
                           loadType: ["third-party"]),
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
