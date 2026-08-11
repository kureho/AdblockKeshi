import Foundation
@testable import AdblockKeshi

/// テスト用のルール生成。
///
/// D-lite 以前は `ReportedRuleBuilder.blockRule(forURL:)` を「ルールの工場」としても
/// 使い回していたが、自己報告ファストレーンごと廃止した。ルール自体（CDN 由来の
/// global host-block）は現役なので、テストが必要とする形をここで組み立てる。
/// 形式はサーバ側 reported-rules / 標準フィルタと同一:
///   `^[^:]+://+([^:/]+\.)?<escaped-host>[/:]`
enum TestRuleFactory {

    /// 報告 host を block する resource-type 群。
    /// `document` を**意図的に除外**して top-level ページ自体の遮断を防ぐ。
    static let blockableResourceTypes =
        ["image", "style-sheet", "script", "font", "raw", "svg-document", "media", "popup"]

    static func hostBlockRule(_ host: String) -> ContentBlockerRule {
        let escaped = host.replacingOccurrences(of: ".", with: #"\."#)
        return ContentBlockerRule(
            trigger: .init(urlFilter: #"^[^:]+://+([^:/]+\.)?"# + escaped + "[/:]",
                           resourceType: blockableResourceTypes,
                           loadType: ["third-party"]),
            action: .init(type: "block")
        )
    }

    /// document まで巻き込む旧形式（危険ルール）。safety filter の検証用。
    static func documentBlockingRule(_ host: String) -> ContentBlockerRule {
        let escaped = host.replacingOccurrences(of: ".", with: #"\."#)
        return ContentBlockerRule(
            trigger: .init(urlFilter: #"^[^:]+://+([^:/]+\.)?"# + escaped + "[/:]"),
            action: .init(type: "block")
        )
    }
}
