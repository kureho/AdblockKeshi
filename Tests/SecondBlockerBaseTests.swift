import XCTest
@testable import AdblockKeshi

/// A-88 ①: 2 本目のブロッカー（報告反映）の土台 = 広告の残り（トグル別）→ ポップアップ対策。
/// 基本保護に入り切らない広告ルールを 2 本目に載せる。並びは scripts/build_split_rules.py と対になる
/// （ポップアップ対策の許可ドメイン宛ての広告ルールは基本保護側に寄せてあるので、後ろに置いてよい）。
final class SecondBlockerBaseTests: XCTestCase {

    private func block(_ host: String) -> ContentBlockerRule {
        ContentBlockerRule(trigger: .init(urlFilter: "^https?://\(host)/"), action: .init(type: "block"))
    }
    private func decode(_ d: Data) throws -> [ContentBlockerRule] {
        try JSONDecoder().decode([ContentBlockerRule].self, from: d)
    }

    // MARK: - どの残りを載せるか（基本保護の variant と対）

    func test_remainder_follows_the_basic_variant() {
        XCTAssertEqual(SecondBlockerBase.adsRemainderFilename(
            for: BlockerTogglesState(adEnabled: true, securityEnabled: true)), "second-ads-sec.json")
        XCTAssertEqual(SecondBlockerBase.adsRemainderFilename(
            for: BlockerTogglesState(adEnabled: true, securityEnabled: false)), "second-ads.json")
    }

    func test_no_remainder_when_ads_are_off() {
        XCTAssertNil(SecondBlockerBase.adsRemainderFilename(
            for: BlockerTogglesState(adEnabled: false, securityEnabled: true)))
        XCTAssertNil(SecondBlockerBase.adsRemainderFilename(
            for: BlockerTogglesState(adEnabled: false, securityEnabled: false)))
    }

    // MARK: - 組み立て

    func test_compose_puts_the_remainder_before_popunder() throws {
        let remainder = try JSONEncoder().encode([block("a.test"), block("b.test")])
        let popunder = try JSONEncoder().encode([block("pop.test")])
        let base = try SecondBlockerBase.compose(adsRemainder: remainder, popunder: popunder)
        XCTAssertEqual(try decode(base), [block("a.test"), block("b.test"), block("pop.test")])
    }

    /// ポップアップ対策は CDN から来る生の JSON。デコードし直すと型に無いキーが落ちるので、バイト列のまま繋ぐ。
    func test_compose_keeps_popunder_bytes_verbatim() throws {
        let remainder = try JSONEncoder().encode([block("a.test")])
        let popunderText = #"[{"trigger":{"url-filter":".*","if-domain":["*tube.test"],"x-unknown":1},"action":{"type":"block"}}]"#
        let base = try SecondBlockerBase.compose(adsRemainder: remainder, popunder: Data(popunderText.utf8))
        let text = try XCTUnwrap(String(data: base, encoding: .utf8))
        XCTAssertTrue(text.hasSuffix(String(popunderText.dropFirst())), text)
        XCTAssertEqual(try decode(base).count, 2)
    }

    func test_compose_without_remainder_is_popunder_as_is() throws {
        let popunder = try JSONEncoder().encode([block("pop.test")])
        XCTAssertEqual(try SecondBlockerBase.compose(adsRemainder: nil, popunder: popunder), popunder)
    }

    func test_compose_with_empty_remainder_or_empty_popunder() throws {
        let popunder = try JSONEncoder().encode([block("pop.test")])
        XCTAssertEqual(try decode(SecondBlockerBase.compose(adsRemainder: Data("[]".utf8), popunder: popunder)),
                       [block("pop.test")])
        let remainder = try JSONEncoder().encode([block("a.test")])
        XCTAssertEqual(try decode(SecondBlockerBase.compose(adsRemainder: remainder, popunder: Data("[ ]".utf8))),
                       [block("a.test")])
    }

    func test_compose_rejects_a_remainder_that_is_not_an_array() {
        XCTAssertThrowsError(try SecondBlockerBase.compose(adsRemainder: Data(#"{"a":1}"#.utf8),
                                                           popunder: Data("[]".utf8)))
    }

    // MARK: - 更新後の作り直し

    func test_regenerate_after_a_remainder_file_is_updated() {
        XCTAssertTrue(SecondBlockerBase.needsRegenerate(afterApplying: ["merged-rules.json", "second-ads.json"]))
        XCTAssertTrue(SecondBlockerBase.needsRegenerate(afterApplying: ["second-ads-sec.json"]))
        XCTAssertFalse(SecondBlockerBase.needsRegenerate(afterApplying: ["merged-rules.json", "ad-rules.json"]))
        XCTAssertFalse(SecondBlockerBase.needsRegenerate(afterApplying: []))
    }
}
