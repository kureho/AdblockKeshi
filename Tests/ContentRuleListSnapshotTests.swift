import XCTest
@testable import AdblockKeshi

/// popunder(ポップアップ広告対策)拡張の状態追跡と、任意の有効化ヒントのロジックを固定する。
final class ContentRuleListSnapshotTests: XCTestCase {

    func test_popunder_state_tracked() {
        XCTAssertTrue(ContentRuleListSnapshot.from(base: true, reported: true, popunder: true).popunderEnabled)
        XCTAssertFalse(ContentRuleListSnapshot.from(base: true, reported: true).popunderEnabled)
    }

    func test_mode_is_unaffected_by_popunder() {
        // popunder は core(標準+学習) の判定に影響しない
        XCTAssertEqual(ContentRuleListSnapshot.from(base: true, reported: true, popunder: false).mode, .bothEnabled)
        XCTAssertEqual(ContentRuleListSnapshot.from(base: true, reported: false, popunder: true).mode, .baseOnly)
    }

    func test_suggests_popunder_when_core_on_but_popunder_off() {
        XCTAssertNotNil(ContentRuleListSnapshot.from(base: true, reported: true, popunder: false).popunderSuggestion)
    }

    func test_no_suggestion_when_popunder_already_on() {
        XCTAssertNil(ContentRuleListSnapshot.from(base: true, reported: true, popunder: true).popunderSuggestion)
    }

    func test_no_suggestion_when_core_incomplete() {
        // core 未完了のときは popunder を勧めない（まず標準+学習に集中）
        XCTAssertNil(ContentRuleListSnapshot.from(base: true, reported: false, popunder: false).popunderSuggestion)
        XCTAssertNil(ContentRuleListSnapshot.from(base: false, reported: false, popunder: false).popunderSuggestion)
    }
}
