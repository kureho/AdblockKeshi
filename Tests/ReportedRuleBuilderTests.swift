import XCTest
@testable import AdblockKeshi

/// 自己報告ファストレーン: 報告された広告URLから Safari Content Blocker の host-block ルールを
/// 生成する純粋ロジック。サーバ側 reported-rules と同じ形式
/// `^[^:]+://+([^:/]+\.)?<host>[/:]` を端末でも生成し、報告した本人の端末で即ブロックする。
final class ReportedRuleBuilderTests: XCTestCase {

    func test_builds_host_block_rule_from_url() {
        let rule = ReportedRuleBuilder.blockRule(forURL: "https://ads.example.com/banner?x=1")
        XCTAssertEqual(rule?.action.type, "block")
        XCTAssertEqual(rule?.trigger.urlFilter, #"^[^:]+://+([^:/]+\.)?ads\.example\.com[/:]"#)
    }

    func test_escapes_dots_in_host() {
        let rule = ReportedRuleBuilder.blockRule(forURL: "https://www.foo.co.jp/")
        XCTAssertEqual(rule?.trigger.urlFilter, #"^[^:]+://+([^:/]+\.)?www\.foo\.co\.jp[/:]"#)
    }

    func test_returns_nil_for_invalid_or_hostless_url() {
        XCTAssertNil(ReportedRuleBuilder.blockRule(forURL: ""))
        XCTAssertNil(ReportedRuleBuilder.blockRule(forURL: "not a url"))
        XCTAssertNil(ReportedRuleBuilder.blockRule(forURL: "https:///nohost"))
    }

    /// 安全弁: 重要ドメイン（決済/銀行/大手等）を報告しても自端末でブロックしない。
    func test_returns_nil_for_critical_domain() {
        XCTAssertNil(ReportedRuleBuilder.blockRule(forURL: "https://pay.stripe.com/checkout"))
        XCTAssertNil(ReportedRuleBuilder.blockRule(forURL: "https://www.mizuhobank.co.jp/"))
    }

    /// JSON エンコードが Safari の期待キー（url-filter / type）になること。
    func test_encodes_to_safari_json_keys() throws {
        let rule = try XCTUnwrap(ReportedRuleBuilder.blockRule(forURL: "https://x.test/"))
        let data = try JSONEncoder().encode(rule)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let trigger = obj?["trigger"] as? [String: Any]
        let action = obj?["action"] as? [String: Any]
        XCTAssertEqual(trigger?["url-filter"] as? String, #"^[^:]+://+([^:/]+\.)?x\.test[/:]"#)
        XCTAssertEqual(action?["type"] as? String, "block")
    }

    // MARK: - 2026-06-23 主因修正: 報告URLの host で top-level document を遮断しない

    /// 報告したサイト自体（例: streamtape）を訪れたとき first-party なので遮断されないよう、
    /// 生成ルールは load-type third-party 限定にする。
    func test_generated_rule_is_third_party_only() {
        let rule = ReportedRuleBuilder.blockRule(forURL: "https://streamtape.com/v/abc/x.mp4")
        XCTAssertEqual(rule?.trigger.loadType, ["third-party"])
    }

    /// resource-type に "document" を含めない（含めると top-level ページが落ちる）。
    /// 広告リソース（image/script 等）は引き続きブロック対象。
    func test_generated_rule_excludes_document_resource_type() throws {
        let rule = try XCTUnwrap(ReportedRuleBuilder.blockRule(forURL: "https://streamtape.com/v/abc/x.mp4"))
        let rt = try XCTUnwrap(rule.trigger.resourceType)
        XCTAssertFalse(rt.contains("document"), "document を含めると訪問中ページが遮断される")
        XCTAssertTrue(rt.contains("image"))
        XCTAssertTrue(rt.contains("script"))
    }

    /// 安全形状の不変条件: あらゆる URL について、生成ルールは ReportedRuleSafety で
    /// document-block と判定されない（third-party 限定 + document 除外）。
    func test_every_generated_rule_is_not_document_blocking() throws {
        let urls = [
            "https://streamtape.com/",
            "https://ads.example.com/banner?x=1",
            "https://sub.domain.co.jp/path",
            "https://video-host.net/v/xyz",
        ]
        for u in urls {
            let rule = try XCTUnwrap(ReportedRuleBuilder.blockRule(forURL: u), "\(u)")
            XCTAssertFalse(ReportedRuleSafety.isDocumentBlockingRisk(rule), "\(u) は document を遮断してはいけない")
        }
    }

    /// JSON キーが Safari の load-type / resource-type に一致すること。
    func test_encodes_load_type_and_resource_type_keys() throws {
        let rule = try XCTUnwrap(ReportedRuleBuilder.blockRule(forURL: "https://x.test/"))
        let data = try JSONEncoder().encode(rule)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let trigger = obj?["trigger"] as? [String: Any]
        XCTAssertEqual(trigger?["load-type"] as? [String], ["third-party"])
        let rt = try XCTUnwrap(trigger?["resource-type"] as? [String])
        XCTAssertFalse(rt.contains("document"))
    }

    // MARK: - ReportedRuleSafety 述語

    /// 旧形式（load-type/resource-type 無しの host-block）は document ごと遮断 = risk。
    func test_safety_flags_legacy_unrestricted_block_as_risk() {
        let legacy = ContentBlockerRule(
            trigger: .init(urlFilter: #"^[^:]+://+([^:/]+\.)?streamtape\.com[/:]"#),
            action: .init(type: "block")
        )
        XCTAssertTrue(ReportedRuleSafety.isDocumentBlockingRisk(legacy))
    }

    /// 新形式の安全な block は risk ではない。
    func test_safety_allows_new_safe_block() throws {
        let safe = try XCTUnwrap(ReportedRuleBuilder.blockRule(forURL: "https://streamtape.com/"))
        XCTAssertFalse(ReportedRuleSafety.isDocumentBlockingRisk(safe))
    }

    /// cosmetic（css-display-none）は document を止められないので risk ではない。
    func test_safety_allows_cosmetic_css_rule() {
        let css = ContentBlockerRule(
            trigger: .init(urlFilter: ".*", ifDomain: ["streamtape.com"]),
            action: .init(type: "css-display-none", selector: ".ad-banner")
        )
        XCTAssertFalse(ReportedRuleSafety.isDocumentBlockingRisk(css))
    }
}
