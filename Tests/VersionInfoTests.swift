import XCTest
@testable import AdblockKeshi

final class VersionInfoTests: XCTestCase {

    func test_decodes_iso8601_generated_at_and_rule_count() throws {
        let json = #"""
        {
          "generated_at": "2026-05-30T12:21:08Z",
          "rule_count": 150000,
          "size_bytes": 21334686,
          "blocker_list_sha256": "abc",
          "filters": []
        }
        """#
        let info = try XCTUnwrap(VersionInfoStore.decode(json.data(using: .utf8)!))
        XCTAssertEqual(info.ruleCount, 150000)
        // 2026-05-30T12:21:08Z は UNIX time 1780143668
        XCTAssertEqual(info.generatedAt.timeIntervalSince1970, 1780143668, accuracy: 1.0)
    }

    func test_returns_nil_for_missing_generated_at() {
        let json = #"{"rule_count": 100}"#
        XCTAssertNil(VersionInfoStore.decode(json.data(using: .utf8)!))
    }

    func test_returns_nil_for_invalid_date_string() {
        let json = #"{"generated_at": "not-a-date", "rule_count": 100}"#
        XCTAssertNil(VersionInfoStore.decode(json.data(using: .utf8)!))
    }

    func test_returns_nil_for_garbage_json() {
        let data = "not json".data(using: .utf8)!
        XCTAssertNil(VersionInfoStore.decode(data))
    }

    func test_default_app_group_matches_extension() {
        let store = VersionInfoStore()
        XCTAssertEqual(store.appGroupIdentifier, "group.com.kureho.adblockkeshi.shared")
        XCTAssertEqual(store.filename, "version.json")
    }

    // MARK: - Plan C Chunk 5: moat metrics

    func test_decodes_reported_metrics_when_present() throws {
        let json = #"""
        {
          "generated_at": "2026-05-30T12:21:08Z",
          "rule_count": 150000,
          "reported": {
            "rule_count": 42,
            "added_last_month": 7
          }
        }
        """#
        let info = try XCTUnwrap(VersionInfoStore.decode(json.data(using: .utf8)!))
        let reported = try XCTUnwrap(info.reported)
        XCTAssertEqual(reported.ruleCount, 42)
        XCTAssertEqual(reported.addedLastMonth, 7)
    }

    func test_reported_is_nil_when_section_absent() throws {
        let json = #"""
        {
          "generated_at": "2026-05-30T12:21:08Z",
          "rule_count": 150000
        }
        """#
        let info = try XCTUnwrap(VersionInfoStore.decode(json.data(using: .utf8)!))
        XCTAssertNil(info.reported)
    }

    func test_reported_is_nil_when_section_is_malformed() throws {
        let json = #"""
        {
          "generated_at": "2026-05-30T12:21:08Z",
          "rule_count": 150000,
          "reported": { "rule_count": "not-an-int" }
        }
        """#
        let info = try XCTUnwrap(VersionInfoStore.decode(json.data(using: .utf8)!))
        XCTAssertNil(info.reported)
    }

    // MARK: - moatDisplayText

    private func makeInfo(reported: VersionInfo.ReportedMetrics?) -> VersionInfo {
        VersionInfo(
            generatedAt: Date(timeIntervalSince1970: 1_780_143_668),
            ruleCount: 150_000,
            reported: reported
        )
    }

    func test_moatDisplayText_isNil_whenReportedAbsent() {
        XCTAssertNil(makeInfo(reported: nil).moatDisplayText)
    }

    func test_moatDisplayText_isNil_whenReportedRuleCountIsZero() {
        let info = makeInfo(reported: .init(ruleCount: 0, addedLastMonth: 0))
        XCTAssertNil(info.moatDisplayText)
    }

    func test_moatDisplayText_showsCountOnly_whenNoMonthlyDelta() {
        let info = makeInfo(reported: .init(ruleCount: 42, addedLastMonth: 0))
        XCTAssertEqual(info.moatDisplayText, "報告で追加: 42 件")
    }

    func test_moatDisplayText_appendsMonthlyDelta_whenPositive() {
        let info = makeInfo(reported: .init(ruleCount: 42, addedLastMonth: 7))
        XCTAssertEqual(info.moatDisplayText, "報告で追加: 42 件（先月 +7）")
    }
}
