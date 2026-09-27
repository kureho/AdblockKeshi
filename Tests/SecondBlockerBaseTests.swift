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

    // MARK: - 残りを載せた作り直しに失敗したとき

    private struct CompileFailed: Error {}
    private let remainderBytes = Data(#"[{"remainder":1}]"#.utf8)
    private let popunderBytes = Data(#"[{"popunder":1}]"#.utf8)

    func test_rebuild_uses_the_remainder_when_it_compiles() {
        var calls: [(Data, Bool)] = []
        let result = SecondBlockerBase.rebuild(composed: remainderBytes, popunder: popunderBytes) { base, keep in
            calls.append((base, keep)); return "built"
        }
        XCTAssertEqual(result, "built")
        XCTAssertEqual(calls.map(\.0), [remainderBytes])
        XCTAssertEqual(calls.map(\.1), [true])
    }

    /// 残りが壊れていて作れないと、古い 2 本目が残り続け、新しい報告も「このサイトで一時オフ」も
    /// 2 本目に届かない。ポップアップ対策だけで作り直して、一時オフを効かせる。
    func test_rebuild_falls_back_to_popunder_only_when_the_remainder_fails() {
        var calls: [(Data, Bool)] = []
        let result = SecondBlockerBase.rebuild(composed: remainderBytes, popunder: popunderBytes) { base, keep in
            calls.append((base, keep))
            if base == self.remainderBytes { throw CompileFailed() }
            return "popunder only"
        }
        XCTAssertEqual(result, "popunder only")
        XCTAssertEqual(calls.map(\.0), [remainderBytes, popunderBytes])
        XCTAssertEqual(calls.map(\.1), [true, false])
    }

    func test_rebuild_without_a_remainder_builds_popunder_only_once() {
        var calls: [(Data, Bool)] = []
        let result = SecondBlockerBase.rebuild(composed: nil, popunder: popunderBytes) { base, keep in
            calls.append((base, keep)); return "popunder only"
        }
        XCTAssertEqual(result, "popunder only")
        XCTAssertEqual(calls.map(\.0), [popunderBytes])
        XCTAssertEqual(calls.map(\.1), [false])
    }

    /// コンパイル待ちのタイムアウト（バックグラウンドで止められた等）は一時的な失敗。ここでポップアップ対策だけで
    /// 作り直すと、報告も一時オフも無い人は 2 本目の combined が消え、次に作り直すまで広告の残りと
    /// 詐欺サイト対策が効かなくなる。前の 2 本目を残して何もしない。
    func test_rebuild_keeps_the_previous_list_when_the_remainder_fails_transiently() {
        struct Timeout: Error {}
        var calls: [Data] = []
        let result: String? = SecondBlockerBase.rebuild(composed: remainderBytes, popunder: popunderBytes,
                                                        isTransient: { $0 is Timeout }) { base, _ in
            calls.append(base); throw Timeout()
        }
        XCTAssertNil(result)
        XCTAssertEqual(calls, [remainderBytes])
    }

    func test_rebuild_gives_up_when_both_fail() {
        let result: String? = SecondBlockerBase.rebuild(composed: remainderBytes, popunder: popunderBytes) { _, _ in
            throw CompileFailed()
        }
        XCTAssertNil(result)
    }
}
