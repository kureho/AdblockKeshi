import XCTest
@testable import AdblockKeshi

/// 統合テスト: 「実 App Group コンテナ」へ、報告反映 Extension が読むのと同じ
/// rules-reported.json を Safari 形式で書けることを検証する。
/// （単体テストは temp dir。ここは実コンテナ到達性 + 実FS書き込みを app プロセスで確かめる）
///
/// D-lite: 供給源は自己報告ではなくサーバ検証済みの `rules-global.json`。
final class ReportedRulesAppGroupIntegrationTests: XCTestCase {

    private let appGroup = "group.com.kureho.adblockkeshi.shared"

    func test_real_app_group_container_round_trips_reported_rule() throws {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        else {
            throw XCTSkip("App Group コンテナがこのテストホストで利用不可")
        }

        // 実コンテナ内の一時 subdir で round-trip（本物の rules-* を汚さない）
        let subdir = container.appendingPathComponent("selftest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: subdir) }

        let store = SelfReportedRulesStore(directory: subdir)
        let rule = TestRuleFactory.hostBlockRule("example.org")
        try JSONEncoder().encode([rule])
            .write(to: subdir.appendingPathComponent(SelfReportedRulesStore.globalFilename))

        XCTAssertTrue(try store.rebuildMerged())

        // merged のファイル名(rules-reported.json)で、実FS上に出来ていること
        let mergedURL = subdir.appendingPathComponent(SelfReportedRulesStore.mergedFilename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: mergedURL.path),
                      "rules-reported.json が実コンテナFSに書かれていない")

        // Safari が解釈できる JSON 形式（url-filter / type）であること
        let data = try Data(contentsOf: mergedURL)
        let arr = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        )
        XCTAssertEqual(arr.count, 1)
        let trigger = arr.first?["trigger"] as? [String: Any]
        let action = arr.first?["action"] as? [String: Any]
        XCTAssertEqual(trigger?["url-filter"] as? String,
                       #"^[^:]+://+([^:/]+\.)?example\.org[/:]"#)
        XCTAssertEqual(action?["type"] as? String, "block")
    }

    /// D-lite: 報告しても、その端末の自己リストへは何も書かれない。
    /// 実コンテナの `rules-self.json` が purge 後に空のままであることを実FSで確かめる。
    func test_selfRulesFile_staysEmptyAfterPurge() throws {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        else {
            throw XCTSkip("App Group コンテナがこのテストホストで利用不可")
        }

        let subdir = container.appendingPathComponent("selftest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: subdir) }

        let store = SelfReportedRulesStore(directory: subdir)
        // 旧版が書いた自己報告ルールが残っている端末を再現。
        try JSONEncoder().encode([TestRuleFactory.hostBlockRule("ads.example.com")])
            .write(to: subdir.appendingPathComponent(SelfReportedRulesStore.selfFilename))

        XCTAssertTrue(try store.purgeSelfRules())

        XCTAssertTrue(store.loadSelfRules().isEmpty)
        XCTAssertTrue(store.loadMergedRules().isEmpty, "global が無い端末では merged も空になる")
    }
}
