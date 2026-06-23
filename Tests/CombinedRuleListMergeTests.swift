import XCTest
@testable import AdblockKeshi

/// 標準ルール + 自己学習ルールの結合（byte-splice / truncation）の純粋ロジック。
final class CombinedRuleListMergeTests: XCTestCase {

    private func block(_ host: String) -> ContentBlockerRule {
        ContentBlockerRule(trigger: .init(urlFilter: "^https?://\(host)/"), action: .init(type: "block"))
    }
    private func cosmetic(_ domain: String) -> ContentBlockerRule {
        ContentBlockerRule(trigger: .init(urlFilter: ".*", ifDomain: [domain]),
                           action: .init(type: "css-display-none", selector: ".ad"))
    }
    private func decode(_ d: Data) throws -> [ContentBlockerRule] {
        try JSONDecoder().decode([ContentBlockerRule].self, from: d)
    }

    func test_splice_appends_reported_to_nonempty_standard() throws {
        let standard = [block("a.test"), block("b.test")]
        let std = try JSONEncoder().encode(standard)
        let reported = [block("c.test")]
        let out = try CombinedRuleListMerge.splice(standardJSON: std, appending: reported)
        XCTAssertEqual(try decode(out), standard + reported)
    }

    func test_splice_into_empty_standard_array() throws {
        let std = Data("[]".utf8)
        let reported = [block("c.test"), block("d.test")]
        let out = try CombinedRuleListMerge.splice(standardJSON: std, appending: reported)
        XCTAssertEqual(try decode(out), reported)
    }

    func test_splice_with_no_reported_returns_standard_bytes_unchanged() throws {
        let std = try JSONEncoder().encode([block("a.test")])
        let out = try CombinedRuleListMerge.splice(standardJSON: std, appending: [])
        XCTAssertEqual(out, std) // full decode せずバイト列そのまま
    }

    func test_splice_tolerates_trailing_whitespace() throws {
        var std = try JSONEncoder().encode([block("a.test")])
        std.append(contentsOf: "\n  ".utf8)
        let out = try CombinedRuleListMerge.splice(standardJSON: std, appending: [block("c.test")])
        XCTAssertEqual(try decode(out), [block("a.test"), block("c.test")])
    }

    /// byte-splice の結果は「decode→連結→encode」と意味的に等価（順序保持・cosmetic も round-trip）。
    func test_splice_equivalent_to_decode_merge() throws {
        let standard = [block("a.test"), cosmetic("b.test"), block("c.test")]
        let std = try JSONEncoder().encode(standard)
        let reported = [block("ad1.test"), block("ad2.test")]
        let out = try CombinedRuleListMerge.splice(standardJSON: std, appending: reported)
        XCTAssertEqual(try decode(out), standard + reported)
    }

    func test_truncatedMerge_keeps_prefix_then_appends_reported() throws {
        let standard = (0..<10).map { block("s\($0).test") }
        let reported = [block("r0.test"), block("r1.test")]
        let out = try CombinedRuleListMerge.truncatedMerge(standardRules: standard, keepStandard: 5, reported: reported)
        XCTAssertEqual(try decode(out), Array(standard.prefix(5)) + reported)
    }

    func test_truncatedMerge_keep_zero() throws {
        let standard = [block("s0.test")]
        let reported = [block("r0.test")]
        let out = try CombinedRuleListMerge.truncatedMerge(standardRules: standard, keepStandard: 0, reported: reported)
        XCTAssertEqual(try decode(out), reported)
    }
}
