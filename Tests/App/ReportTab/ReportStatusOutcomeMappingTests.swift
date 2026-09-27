import XCTest
@testable import AdblockKeshi

/// A-88 §3: `POST /v1/reports/status` が返す 5 値（checking/applied/in_app_ad/site_own_ad/declined）
/// を、履歴表示用の `ReportStatus` へ丸める対応表を固定する。
/// 設計 `tasks/a88-design-2026-09-27.md` §3・進め方4 の対応表どおり。
final class ReportStatusOutcomeMappingTests: XCTestCase {

    func test_checking_mapsToCheckingCase() {
        XCTAssertEqual(ReportStatus.fromServerOutcome("checking"), .checking)
    }

    /// applied は「今の approved と同じ見た目でよい」（設計 §3 明記）ので既存 case を再利用する。
    func test_applied_mapsToExistingApprovedCase() {
        XCTAssertEqual(ReportStatus.fromServerOutcome("applied"), .approved)
    }

    func test_inAppAd_mapsToInAppAdCase() {
        XCTAssertEqual(ReportStatus.fromServerOutcome("in_app_ad"), .inAppAd)
    }

    func test_siteOwnAd_mapsToSiteOwnAdCase() {
        XCTAssertEqual(ReportStatus.fromServerOutcome("site_own_ad"), .siteOwnAd)
    }

    func test_declined_mapsToDeclinedCase() {
        XCTAssertEqual(ReportStatus.fromServerOutcome("declined"), .declined)
    }

    /// 未知の値（将来サーバが値を増やした等）は nil。呼び出し側はこの行の更新をスキップし、
    /// 今の表示のまま保つ（fail-safe。ReportStatus 自体の Decodable init と同じ考え方）。
    func test_unknownOutcome_returnsNil() {
        XCTAssertNil(ReportStatus.fromServerOutcome("some_future_outcome"))
    }

    func test_checking_displayLabel() {
        XCTAssertEqual(ReportStatus.checking.displayLabel, "確認中")
    }

    func test_inAppAd_displayLabel_and_detailMentionsInAppAdBlocker() {
        XCTAssertEqual(ReportStatus.inAppAd.displayLabel, "アプリ内広告")
        XCTAssertTrue(ReportStatus.inAppAd.detailDescription.contains("アプリ内広告ブロック"),
                      "Safari のブロックでは消せない旨と代替機能の案内を含めること")
    }

    func test_siteOwnAd_displayLabel_and_detailMentionsSiteBreakage() {
        XCTAssertEqual(ReportStatus.siteOwnAd.displayLabel, "サイト自身の広告")
        XCTAssertTrue(ReportStatus.siteOwnAd.detailDescription.contains("壊れ"),
                      "止めるとページが壊れるため対象外である旨を含めること")
    }

    func test_declined_displayLabel_and_detail() {
        XCTAssertEqual(ReportStatus.declined.displayLabel, "見送り")
        XCTAssertTrue(ReportStatus.declined.detailDescription.contains("見送り"))
    }

    /// 既存 raw 値（pending/validating/approved/rejected_*）は旧データのデコードのため残す。
    func test_legacyRawValuesStillDecode() throws {
        for raw in ["pending", "validating", "approved", "rejected_no_ad_detected", "rejected_safety_gate"] {
            let json = Data("[\"\(raw)\"]".utf8)
            XCTAssertNoThrow(try JSONDecoder().decode([ReportStatus].self, from: json), raw)
        }
    }

    /// 新しい raw 値も他の case 同様 JSON 往復できる（永続化・decode の対称性）。
    func test_newCases_roundTripThroughJSON() throws {
        for status: ReportStatus in [.checking, .inAppAd, .siteOwnAd, .declined] {
            let data = try JSONEncoder().encode([status])
            let decoded = try JSONDecoder().decode([ReportStatus].self, from: data)
            XCTAssertEqual(decoded, [status])
        }
    }
}
