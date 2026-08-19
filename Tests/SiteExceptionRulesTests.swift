import XCTest
@testable import AdblockKeshi

/// SiteExceptionRules（per-site 例外ルール生成）と BasicExceptionRegenPlan（基本保護の
/// combined 再生成計画）のテスト。
///
/// ★安全上の不変条件: 例外機構は **ignore-previous-rules しか生成しない**。
/// SiteExceptionsStore 由来のデータがブロックを「強める」方向に働く経路を作らない
/// （DNS 自己報告ファストレーンが報告サイト自体を壊した 4.0.2 事故の教訓の裏返し）。
final class SiteExceptionRulesTests: XCTestCase {

    // MARK: - SiteExceptionRules

    func test_rules_emptyDomains_returnsEmpty() {
        XCTAssertTrue(SiteExceptionRules.rules(for: []).isEmpty)
    }

    func test_rules_singleDomain_buildsIgnorePreviousRulesForDomainAndSubdomains() throws {
        let rules = SiteExceptionRules.rules(for: ["news.example.com"])
        XCTAssertEqual(rules.count, 1)
        let rule = try XCTUnwrap(rules.first)
        XCTAssertEqual(rule.action.type, "ignore-previous-rules")
        XCTAssertEqual(rule.trigger.urlFilter, ".*")
        XCTAssertEqual(rule.trigger.ifDomain, ["*news.example.com"],
                       "先頭 * で subdomain も対象（Safari の if-domain 仕様）")
        XCTAssertNil(rule.action.selector)
        XCTAssertNil(rule.trigger.unlessDomain)
    }

    func test_rules_preserveInputOrder() {
        let rules = SiteExceptionRules.rules(for: ["b.example.net", "a.example.com"])
        XCTAssertEqual(rules.map(\.trigger.ifDomain), [["*b.example.net"], ["*a.example.com"]])
    }

    func test_rules_skipEmptyDomains() {
        XCTAssertEqual(SiteExceptionRules.rules(for: ["", "a.example.com", "  "]).count, 1)
    }

    /// 不変条件そのものを固定: どんな入力でも block アクションは生成されない。
    func test_rules_neverProduceBlockActions() {
        let hostile = ["evil.example", "a.b.c.d.example.co.jp", "xn--wgv71a119e.jp"]
        for rule in SiteExceptionRules.rules(for: hostile) {
            XCTAssertEqual(rule.action.type, "ignore-previous-rules")
        }
    }

    /// Safari が受理する JSON 形になっていること（キー名は ContentBlockerRule の CodingKeys 経由）。
    func test_rules_encodeToSafariContentBlockerJSON() throws {
        let data = try JSONEncoder().encode(SiteExceptionRules.rules(for: ["news.example.com"]))
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let trigger = try XCTUnwrap(json.first?["trigger"] as? [String: Any])
        XCTAssertEqual(trigger["url-filter"] as? String, ".*")
        XCTAssertEqual(trigger["if-domain"] as? [String], ["*news.example.com"])
        let action = try XCTUnwrap(json.first?["action"] as? [String: Any])
        XCTAssertEqual(action["type"] as? String, "ignore-previous-rules")
    }

    // MARK: - BasicExceptionRegenPlan

    func test_plan_noExceptions_returnsNil() {
        XCTAssertNil(BasicExceptionRegenPlan.plan(
            state: BlockerTogglesState(adEnabled: true, securityEnabled: true),
            hasExceptions: false))
    }

    func test_plan_bothTogglesOff_returnsNil() {
        XCTAssertNil(BasicExceptionRegenPlan.plan(
            state: BlockerTogglesState(adEnabled: false, securityEnabled: false),
            hasExceptions: true),
            "empty variant は常に bundle の no-op（例外を足すものが無い）")
    }

    func test_plan_merged_isNotTruncating() throws {
        let plan = try XCTUnwrap(BasicExceptionRegenPlan.plan(
            state: BlockerTogglesState(adEnabled: true, securityEnabled: true),
            hasExceptions: true))
        XCTAssertEqual(plan.variantFilename, "merged-rules.json")
        XCTAssertFalse(plan.mayTruncate)
    }

    func test_plan_adOnly_isTruncating() throws {
        let plan = try XCTUnwrap(BasicExceptionRegenPlan.plan(
            state: BlockerTogglesState(adEnabled: true, securityEnabled: false),
            hasExceptions: true))
        XCTAssertEqual(plan.variantFilename, "ad-rules.json")
        XCTAssertTrue(plan.mayTruncate, "ad-only は標準が 150,000 上限ちょうど（budget 必須）")
    }

    func test_plan_securityOnly_isNotTruncating() throws {
        let plan = try XCTUnwrap(BasicExceptionRegenPlan.plan(
            state: BlockerTogglesState(adEnabled: false, securityEnabled: true),
            hasExceptions: true))
        XCTAssertEqual(plan.variantFilename, "security-rules.json")
        XCTAssertFalse(plan.mayTruncate)
    }
}
