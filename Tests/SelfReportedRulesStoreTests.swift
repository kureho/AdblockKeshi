import XCTest
@testable import AdblockKeshi

/// 自己報告ファストレーンの保存層。
/// 自己報告ルール(rules-self.json)とグローバル配信ルール(rules-global.json)を union し、
/// 報告Extensionが読む rules-reported.json を書き出す。重複は url-filter で排除。
final class SelfReportedRulesStoreTests: XCTestCase {

    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func test_append_writes_merged_file_with_rule() throws {
        let store = SelfReportedRulesStore(directory: dir)
        let rule = try XCTUnwrap(ReportedRuleBuilder.blockRule(forURL: "https://ads.test/"))
        XCTAssertTrue(try store.appendSelfRule(rule))
        XCTAssertEqual(store.loadMergedRules(), [rule])
    }

    func test_append_dedupes_same_rule() throws {
        let store = SelfReportedRulesStore(directory: dir)
        let rule = try XCTUnwrap(ReportedRuleBuilder.blockRule(forURL: "https://ads.test/"))
        XCTAssertTrue(try store.appendSelfRule(rule))
        XCTAssertFalse(try store.appendSelfRule(rule))
        XCTAssertEqual(store.loadSelfRules().count, 1)
    }

    func test_rebuild_merges_self_and_global_deduped() throws {
        let store = SelfReportedRulesStore(directory: dir)
        let a = try XCTUnwrap(ReportedRuleBuilder.blockRule(forURL: "https://a.test/"))
        let b = try XCTUnwrap(ReportedRuleBuilder.blockRule(forURL: "https://b.test/"))
        try JSONEncoder().encode([a, b]).write(to: dir.appendingPathComponent("rules-global.json"))
        XCTAssertTrue(try store.appendSelfRule(a)) // a は global と重複
        let merged = Set(store.loadMergedRules().map { $0.trigger.urlFilter })
        XCTAssertEqual(merged, Set([a, b].map { $0.trigger.urlFilter }))
    }

    /// 保存先 merged ファイル名が、Extension が読むファイル名と一致していること（silent failure 防止）。
    func test_merged_filename_matches_resolver_filename() {
        XCTAssertEqual(SelfReportedRulesStore.mergedFilename, ReportedRulesResolver.filename)
    }
}
