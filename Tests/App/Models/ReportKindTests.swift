import XCTest
@testable import AdblockKeshi

/// ReportKind（報告種別）のテスト。
/// rawValue はサーバ (`workers/src/lib/report-kind.ts` の `REPORT_KINDS`) と完全同期。
/// ずれるとサーバが値を認識できず、壊れ報告が広告報告（既定値）として扱われ、
/// 広告集約の母集団を「壊れているサイト」で汚染する。
final class ReportKindTests: XCTestCase {

    func test_rawValues_matchServerContract() {
        XCTAssertEqual(ReportKind.adNotBlocked.rawValue, "ad_not_blocked")
        XCTAssertEqual(ReportKind.siteBroken.rawValue, "site_broken")
    }

    func test_defaultOrder_adNotBlockedFirst() {
        XCTAssertEqual(ReportKind.allCases.first, .adNotBlocked,
                       "既定の並びは従来の広告報告が先頭（主用途を変えない）")
        XCTAssertEqual(ReportKind.allCases.count, 2)
    }

    func test_titles_areNonEmpty_andDistinct() {
        let titles = ReportKind.allCases.map(\.title)
        XCTAssertFalse(titles.contains(where: \.isEmpty))
        XCTAssertEqual(Set(titles).count, titles.count)
    }

    func test_details_areNonEmpty() {
        XCTAssertFalse(ReportKind.allCases.map(\.detail).contains(where: \.isEmpty))
    }

    /// 壊れ報告は「広告の種類」を持たない（フォームで ad_type を要求しない根拠）。
    func test_requiresAdType_onlyForAdNotBlocked() {
        XCTAssertTrue(ReportKind.adNotBlocked.requiresAdType)
        XCTAssertFalse(ReportKind.siteBroken.requiresAdType)
    }
}
