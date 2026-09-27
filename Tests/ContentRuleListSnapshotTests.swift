import XCTest
@testable import AdblockKeshi

/// popunder(ポップアップ広告対策)拡張の状態追跡と、任意の有効化ヒントのロジックを固定する。
/// 4→3 統合後、状態は「標準(自己学習込み) ON/OFF」の 2 値（baseOnly/reportedOnly は廃止）。
final class ContentRuleListSnapshotTests: XCTestCase {

    func test_popunder_state_tracked() {
        XCTAssertTrue(ContentRuleListSnapshot.from(base: true, popunder: true).popunderEnabled)
        XCTAssertFalse(ContentRuleListSnapshot.from(base: true).popunderEnabled)
    }

    func test_mode_reflects_base_and_is_unaffected_by_popunder() {
        XCTAssertEqual(ContentRuleListSnapshot.from(base: true, popunder: false).mode, .bothEnabled)
        // popunder は core(標準+学習) の判定に影響しない
        XCTAssertEqual(ContentRuleListSnapshot.from(base: false, popunder: true).mode, .bothDisabled)
    }

    func test_suggests_popunder_when_core_on_but_popunder_off() {
        XCTAssertNotNil(ContentRuleListSnapshot.from(base: true, popunder: false).popunderSuggestion)
    }

    /// A-88 ①: 基本保護に入り切らない広告の残りは報告反映に載る＝案内はそれも伝える。
    func test_suggestion_mentions_the_ads_that_only_the_second_blocker_carries() {
        guard case .yellow(let text)? = ContentRuleListSnapshot.from(base: true, popunder: false).popunderSuggestion else {
            return XCTFail("案内が出ていない")
        }
        XCTAssertTrue(text.contains("さらに多くの広告"), text)
        XCTAssertTrue(text.contains("広告サイトへ飛ばされる誘導"), text)
    }

    func test_no_suggestion_when_popunder_already_on() {
        XCTAssertNil(ContentRuleListSnapshot.from(base: true, popunder: true).popunderSuggestion)
    }

    func test_no_suggestion_when_core_off() {
        XCTAssertNil(ContentRuleListSnapshot.from(base: false, popunder: false).popunderSuggestion)
    }
}
