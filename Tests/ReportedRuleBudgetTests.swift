import XCTest
@testable import AdblockKeshi

/// 統合 Content Blocker のルール予算（純粋ロジック）。
/// 標準 + 自己学習を 150,000 上限内に配分。reported に予約枠を保証し、標準を際限なく削らない。
final class ReportedRuleBudgetTests: XCTestCase {

    /// 報告順（oldest→newest）の安全な reported ルールを n 件生成。
    private func reported(_ n: Int) -> [ContentBlockerRule] {
        (0..<n).compactMap { ReportedRuleBuilder.blockRule(forURL: "https://ad\($0).test/") }
    }

    func test_no_truncation_when_combined_under_cap() {
        let r = reported(3)
        let p = ReportedRuleBudget.plan(standardCount: 130_000, reportedSafe: r)
        XCTAssertEqual(p.standardKeep, 130_000)
        XCTAssertEqual(p.reportedKeep.count, 3)
        XCTAssertEqual(p.droppedStandard, 0)
        XCTAssertEqual(p.droppedReported, 0)
        XCTAssertFalse(p.needsTruncation)
        XCTAssertEqual(p.combinedCount, 130_003)
    }

    /// ad モード（標準 150,000）では標準を truncate するが、削るのは reported が占める分だけ。
    func test_truncates_standard_only_by_reported_amount_in_ad_mode() {
        let r = reported(10)
        let p = ReportedRuleBudget.plan(standardCount: 150_000, reportedSafe: r)
        XCTAssertTrue(p.needsTruncation)
        XCTAssertEqual(p.reportedKeep.count, 10)
        XCTAssertEqual(p.standardKeep, ReportedRuleBudget.totalCap - 10) // 148,990
        XCTAssertEqual(p.droppedStandard, 1_010)
        XCTAssertEqual(p.combinedCount, ReportedRuleBudget.totalCap)
    }

    /// combined は totalCap を絶対に超えない（あらゆる入力で）。
    func test_combined_never_exceeds_total_cap() {
        for (sc, rc) in [(0, 0), (150_000, 0), (150_000, 2_000), (150_000, 5_000), (130_000, 2_500), (149_500, 100)] {
            let p = ReportedRuleBudget.plan(standardCount: sc, reportedSafe: reported(rc))
            XCTAssertLessThanOrEqual(p.combinedCount, ReportedRuleBudget.totalCap, "sc=\(sc) rc=\(rc)")
        }
    }

    /// reported が予約枠を超えたら、新しさ（insertion order の末尾）を優先保持し、超過分を drop。
    func test_reported_reserve_keeps_newest_and_records_dropped() {
        let r = reported(2_500) // reserve(2,000) 超過
        let p = ReportedRuleBudget.plan(standardCount: 150_000, reportedSafe: r)
        XCTAssertEqual(p.reportedKeep.count, ReportedRuleBudget.reportedReserve)
        XCTAssertEqual(p.droppedReported, 500)
        // 新しさ優先 = 末尾 reserve 件（r[500...2499]）を順序保持
        XCTAssertEqual(p.reportedKeep, Array(r.suffix(ReportedRuleBudget.reportedReserve)))
    }

    /// 標準は floor 未満には削らない（reported が最大でも standardFloor は残る）。
    func test_standard_never_below_floor() {
        let p = ReportedRuleBudget.plan(standardCount: 150_000, reportedSafe: reported(10_000))
        XCTAssertGreaterThanOrEqual(p.standardKeep, ReportedRuleBudget.standardFloor)
        XCTAssertEqual(p.standardKeep, ReportedRuleBudget.standardFloor) // 147,000
        XCTAssertEqual(p.reportedKeep.count, ReportedRuleBudget.reportedReserve)
    }

    /// 標準が少ない state（security/empty）では truncation なし・reported は全件（reserve 内）。
    func test_small_standard_keeps_all_reported() {
        let p0 = ReportedRuleBudget.plan(standardCount: 0, reportedSafe: reported(50))
        XCTAssertEqual(p0.standardKeep, 0)
        XCTAssertEqual(p0.reportedKeep.count, 50)
        XCTAssertFalse(p0.needsTruncation)

        let pSec = ReportedRuleBudget.plan(standardCount: 30_000, reportedSafe: reported(500))
        XCTAssertEqual(pSec.standardKeep, 30_000)
        XCTAssertEqual(pSec.reportedKeep.count, 500)
        XCTAssertFalse(pSec.needsTruncation)
    }
}
