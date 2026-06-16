import XCTest
@testable import AdblockKeshi

/// グローバル報告フィルタ取得の配線契約を固定する。
/// URL/ファイル名がずれると「グローバル分が端末に届かない」silent failure になる。
final class ReportedGlobalSyncConstantsTests: XCTestCase {

    func test_reported_cdn_url_points_at_rules_reported_json() {
        XCTAssertEqual(
            FilterDownloader.reportedURL.absoluteString,
            "https://kureho.github.io/AdblockKeshi/cdn/rules-reported.json"
        )
    }

    /// グローバル取得は merged(rules-reported.json) とは別ファイルに保存してから union する。
    /// 直接 merged に上書きすると自己報告が消えるため、分離していることを保証する。
    func test_global_filename_is_separate_from_merged() {
        XCTAssertEqual(SelfReportedRulesStore.globalFilename, "rules-global.json")
        XCTAssertNotEqual(SelfReportedRulesStore.globalFilename, SelfReportedRulesStore.mergedFilename)
    }
}
