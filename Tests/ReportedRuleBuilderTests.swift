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
}
