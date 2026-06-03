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
}
