import XCTest
@testable import AdblockKeshi

/// RuleUpdater の純ロジック（manifest 解析・sha 比較・ルール数ガード）のテスト。
/// CDN の実配信フォーマット（version.json / version-security.json）を fixture として使う。
final class RuleUpdatePlannerTests: XCTestCase {

    // MARK: - fixtures（docs/cdn の実フォーマットを踏襲）

    private let versionJSON = Data("""
    {
      "generated_at": "2026-07-01T07:06:49Z",
      "rule_count": 150000,
      "size_bytes": 22371497,
      "blocker_list_sha256": "f5930c6c49864305ac6c7c29dd293448c6ee86f49f53114bb36d8bffcd3e8a8a",
      "filters": [{"name": "easylist", "license": "CC-BY-SA-3.0"}],
      "reported": {"rule_count": 0, "added_last_month": 0}
    }
    """.utf8)

    /// version-security.json の generated_at は小数秒付き ISO8601（Python isoformat）である点に注意。
    private let versionSecurityJSON = Data("""
    {
      "security-rules_sha256": "15e3e836898bf646e25518e0e2e36bfd895c09a56d50f9610f677a9299ec951f",
      "security-rules_bytes": 3516979,
      "merged-rules_sha256": "9a4fa4818e2bce46236096dea6745270a3addb45d32988f02480cab33679feaa",
      "merged-rules_bytes": 20434312,
      "empty-rules_sha256": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
      "empty-rules_bytes": 2,
      "generated_at": "2026-06-28T02:05:04.311961Z"
    }
    """.utf8)

    private func plan(_ variant: String, in plans: [RuleVariantPlan]) -> RuleVariantPlan? {
        plans.first { $0.variantFilename == variant }
    }

    // MARK: - manifest 解析

    func test_plans_covers_all_four_variants() throws {
        let plans = try RuleUpdatePlanner.plans(
            versionJSON: versionJSON, versionSecurityJSON: versionSecurityJSON)
        XCTAssertEqual(
            Set(plans.map(\.variantFilename)),
            ["merged-rules.json", "ad-rules.json", "security-rules.json", "empty-rules.json"]
        )
    }

    func test_ad_variant_maps_to_cdn_blockerList_and_version_json_sha() throws {
        let plans = try RuleUpdatePlanner.plans(
            versionJSON: versionJSON, versionSecurityJSON: versionSecurityJSON)
        let ad = try XCTUnwrap(plan("ad-rules.json", in: plans))
        // CDN 上の広告 variant の実体は blockerList.json（monthly-filter-update.yml が生成）
        XCTAssertEqual(
            ad.downloadURL.absoluteString,
            "https://kureho.github.io/AdblockKeshi/cdn/blockerList.json"
        )
        XCTAssertEqual(
            ad.expectedSHA256,
            "f5930c6c49864305ac6c7c29dd293448c6ee86f49f53114bb36d8bffcd3e8a8a"
        )
        // generated_at = 2026-07-01T07:06:49Z
        let formatter = ISO8601DateFormatter()
        XCTAssertEqual(ad.generatedAt, formatter.date(from: "2026-07-01T07:06:49Z"))
    }

    func test_security_variants_map_to_version_security_json() throws {
        let plans = try RuleUpdatePlanner.plans(
            versionJSON: versionJSON, versionSecurityJSON: versionSecurityJSON)
        let merged = try XCTUnwrap(plan("merged-rules.json", in: plans))
        let security = try XCTUnwrap(plan("security-rules.json", in: plans))
        let empty = try XCTUnwrap(plan("empty-rules.json", in: plans))

        XCTAssertEqual(
            merged.downloadURL.absoluteString,
            "https://kureho.github.io/AdblockKeshi/cdn/merged-rules.json"
        )
        XCTAssertEqual(
            merged.expectedSHA256,
            "9a4fa4818e2bce46236096dea6745270a3addb45d32988f02480cab33679feaa"
        )
        XCTAssertEqual(
            security.expectedSHA256,
            "15e3e836898bf646e25518e0e2e36bfd895c09a56d50f9610f677a9299ec951f"
        )
        XCTAssertEqual(
            empty.expectedSHA256,
            "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945"
        )
    }

    func test_plans_parses_fractional_seconds_generated_at() throws {
        // Python isoformat の 6 桁小数秒を parse できること（ISO8601DateFormatter 素のままだと失敗する）
        let plans = try RuleUpdatePlanner.plans(
            versionJSON: versionJSON, versionSecurityJSON: versionSecurityJSON)
        let merged = try XCTUnwrap(plan("merged-rules.json", in: plans))
        let formatter = ISO8601DateFormatter()
        let expected = try XCTUnwrap(formatter.date(from: "2026-06-28T02:05:04Z"))
        XCTAssertEqual(
            merged.generatedAt.timeIntervalSince1970,
            expected.timeIntervalSince1970,
            accuracy: 1.0
        )
    }

    func test_plans_throws_on_missing_sha_key() {
        let broken = Data(#"{"generated_at": "2026-07-01T07:06:49Z", "rule_count": 1}"#.utf8)
        XCTAssertThrowsError(
            try RuleUpdatePlanner.plans(versionJSON: broken, versionSecurityJSON: versionSecurityJSON)
        )
    }

    func test_plans_throws_on_invalid_json() {
        XCTAssertThrowsError(
            try RuleUpdatePlanner.plans(
                versionJSON: Data("not-json".utf8), versionSecurityJSON: versionSecurityJSON)
        )
    }

    // MARK: - sha 比較（差分がある variant のみ DL）

    func test_needsDownload_true_when_no_record() {
        XCTAssertTrue(RuleUpdatePlanner.needsDownload(expectedSHA256: "abc", applied: nil))
    }

    func test_needsDownload_true_when_sha_differs() {
        let record = AppliedRulesRecord(
            sha256: "old", generatedAt: Date(), ruleCount: 100, appliedAt: Date())
        XCTAssertTrue(RuleUpdatePlanner.needsDownload(expectedSHA256: "new", applied: record))
    }

    func test_needsDownload_false_when_sha_matches() {
        let record = AppliedRulesRecord(
            sha256: "same", generatedAt: Date(), ruleCount: 100, appliedAt: Date())
        XCTAssertFalse(RuleUpdatePlanner.needsDownload(expectedSHA256: "same", applied: record))
    }

    // MARK: - ルール数ガード

    func test_ruleCount_below_half_of_baseline_is_rejected() {
        XCTAssertFalse(RuleUpdatePlanner.validateRuleCount(74_999, baseline: 150_000))
        XCTAssertFalse(RuleUpdatePlanner.validateRuleCount(49, baseline: 100))
    }

    func test_ruleCount_at_half_of_baseline_is_accepted() {
        // 「50% 未満なら拒否」= ちょうど 50% は許容
        XCTAssertTrue(RuleUpdatePlanner.validateRuleCount(75_000, baseline: 150_000))
        XCTAssertTrue(RuleUpdatePlanner.validateRuleCount(50, baseline: 100))
    }

    func test_ruleCount_above_webkit_limit_is_rejected() {
        // 150,000 ちょうど（広告 variant の現行実績）は WebKit 上限内 = 許容
        XCTAssertTrue(RuleUpdatePlanner.validateRuleCount(150_000, baseline: 150_000))
        XCTAssertFalse(RuleUpdatePlanner.validateRuleCount(150_001, baseline: 150_000))
    }

    func test_ruleCount_zero_baseline_accepts_empty() {
        // empty variant: 過去実績 0 → 0 件を許容
        XCTAssertTrue(RuleUpdatePlanner.validateRuleCount(0, baseline: 0))
    }

    func test_default_baselines_come_from_ci_pipeline_limits() throws {
        let plans = try RuleUpdatePlanner.plans(
            versionJSON: versionJSON, versionSecurityJSON: versionSecurityJSON)
        XCTAssertEqual(plan("ad-rules.json", in: plans)?.defaultBaselineRuleCount, 150_000)
        XCTAssertEqual(plan("merged-rules.json", in: plans)?.defaultBaselineRuleCount, 130_000)
        XCTAssertEqual(plan("security-rules.json", in: plans)?.defaultBaselineRuleCount, 30_000)
        XCTAssertEqual(plan("empty-rules.json", in: plans)?.defaultBaselineRuleCount, 0)
    }

    // MARK: - sha256 ヘルパ

    func test_sha256Hex_known_vector() {
        // "[]" の sha256 = CDN の empty-rules_sha256 と一致するはず
        XCTAssertEqual(
            RuleUpdatePlanner.sha256Hex(Data("[]".utf8)),
            "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945"
        )
    }
}
