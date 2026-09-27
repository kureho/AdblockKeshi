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

    /// 画面上部の説明文も同じ約束をしていた（「自動で検証して、ブロックリストへ追加します」）。
    /// 報告は週1回の判定を通り、アプリ内広告・サイト自身の広告などは追加されない＝断定しない。
    func test_headerSubtitle_noLongerPromisesGuaranteedAddition() {
        XCTAssertFalse(ReportEntryView.headerSubtitle.contains("ブロックリストへ追加します"),
                       "「必ず追加される」と読める断定表現を残さない")
        XCTAssertTrue(ReportEntryView.headerSubtitle.contains("確認"),
                      "内容を確認してから反映する流れを書く")
    }
}
