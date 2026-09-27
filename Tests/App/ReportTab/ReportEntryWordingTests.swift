import XCTest
@testable import AdblockKeshi

/// A-88 進め方5: 報告画面の約束の文言を「週1回確認して結果を履歴に表示する」実態に合わせる。
/// 旧文言「通常 7〜14 日でブロックリストに追加」は“必ず追加される”と読めるため置き換える。
final class ReportEntryWordingTests: XCTestCase {

    func test_flowStep3Subtitle_noLongerPromisesGuaranteedAddition() {
        XCTAssertFalse(
            ReportEntryView.flowStep3Subtitle.contains("でブロックリストに追加。"),
            "「必ず追加される」と読める断定表現を残さない"
        )
    }

    func test_flowStep3Subtitle_mentionsWeeklyCheckAndHistory() {
        XCTAssertTrue(ReportEntryView.flowStep3Subtitle.contains("週"),
                      "週1回の判定に合わせた表現にする")
        XCTAssertTrue(ReportEntryView.flowStep3Subtitle.contains("履歴"),
                      "結果は履歴で分かる旨を書く")
    }
}
