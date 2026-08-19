import Foundation

/// Safari Content Blocker のルール1件。
/// JSON キーは Safari が要求する `url-filter` / `if-domain` / `resource-type` /
/// `load-type` / `type` / `selector` に一致させる。
/// host-block（action=block）に加え、サーバ昇格の cosmetic（css-display-none + selector）も
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
