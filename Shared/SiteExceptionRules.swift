import Foundation

/// per-site 例外ルールの生成（v4.2.0「このサイトで一時オフ」）。
///
/// ★安全上の不変条件: この機構は **ignore-previous-rules しか生成しない**。
/// SiteExceptionsStore 由来のデータがブロックを「強める」方向に働く経路を作らない
/// （自己報告ファストレーンが報告サイト自体を壊した 4.0.2 事故の教訓の裏返し）。
///
/// 生成ルールは各 Content Blocker のルール配列の **必ず最後尾** に置く
/// （ignore-previous-rules は「それ以前のルール」にしか効かない）。
/// 配置は CombinedRuleListCoordinator が担う。
enum SiteExceptionRules {

    /// ドメイン配列 → 例外ルール配列（入力順を保持・空文字は無視）。
    /// `*<host>` は Safari の if-domain 仕様でそのドメインと全 subdomain に一致する。
    static func rules(for domains: [String]) -> [ContentBlockerRule] {
        domains.compactMap { domain in
            let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return ContentBlockerRule(
                trigger: .init(urlFilter: ".*", ifDomain: ["*" + trimmed]),
                action: .init(type: "ignore-previous-rules")
            )
        }
    }
}

/// 基本保護（.blocker）の combined 再生成計画。
///
/// 基本保護は D-lite 以降 combined を持たない（bundle variant 直参照）が、
/// per-site 例外があるときだけ `combined-<variant>` = 標準 + 例外ルール を生成して
/// `BlockerListResolver.resolve(for:)` の combined 最優先に拾わせる。
enum BasicExceptionRegenPlan {
    struct Plan: Equatable {
        let variantFilename: String
        /// ad-only は標準が 150,000 上限ちょうど → ReportedRuleBudget での切り詰めが必須。
        let mayTruncate: Bool
    }

    /// nil = combined を作らない（例外なし / 両トグル OFF）。
    /// 両トグル OFF の empty variant は resolver が常に bundle の no-op を返す設計
    /// （deep-audit P2）なので、例外を足すものが無い。
    static func plan(state: BlockerTogglesState, hasExceptions: Bool) -> Plan? {
        guard hasExceptions else { return nil }
        guard state.adEnabled || state.securityEnabled else { return nil }
        let variant = BlockerListResolver().filename(for: state)
        return Plan(variantFilename: variant, mayTruncate: variant == "ad-rules.json")
    }
}
