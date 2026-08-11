import Foundation

/// 報告ルールが top-level document（訪問中のページ自体）を遮断し得るかを判定する純粋ロジック。
///
/// CDN(global)・bundle・（D-lite 以前の）自己報告のどの経路から来たルールでも、
/// merged へ書き出す前にこの判定で document ブロックを排除する（防御多層）。
/// 2026-06-23: 報告した広告URLの host を無制限に host-block していたため、ユーザーが
/// 訪問中ページのURL（例: streamtape.com）を報告するとそのページ自体が開けなくなる
/// 事故が発生した。安全な block ルールは「third-party 限定 かつ document を resource-type
/// から除外」していなければならない。
enum ReportedRuleSafety {
    /// document を遮断し得る `block` ルールなら true。
    /// `block` 以外（css-display-none 等の cosmetic）は document のロードを止められないので常に false。
    static func isDocumentBlockingRisk(_ rule: ContentBlockerRule) -> Bool {
        // block 以外（css-display-none 等の cosmetic）は document のロードを止められない。
        guard rule.action.type == "block" else { return false }
        // 安全な block は「resource-type が document を除外」かつ「load-type が third-party 限定」。
        // どちらかでも欠ければ top-level document を遮断し得る = risk。
        let excludesDocument = rule.trigger.resourceType.map { !$0.contains("document") } ?? false
        let thirdPartyOnly = rule.trigger.loadType == ["third-party"]
        return !(excludesDocument && thirdPartyOnly)
    }
}
