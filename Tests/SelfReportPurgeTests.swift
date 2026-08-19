import XCTest
@testable import AdblockKeshi

/// D-lite: 自己報告ファストレーンの廃止。
///
/// 「新規の自己報告を書かない」だけでなく、**既に端末へ書かれた自己報告ルールを掃除する**。
/// ただし `rules-global.json`（サーバ検証を通った L6 の成果物）は絶対に消さない。
final class SelfReportPurgeTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func hostBlockRule(_ host: String) -> ContentBlockerRule {
        let escaped = host.replacingOccurrences(of: ".", with: #"\."#)
        return ContentBlockerRule(
            trigger: .init(urlFilter: #"^[^:]+://+([^:/]+\.)?"# + escaped + "[/:]",
                           resourceType: ["image", "script"],
                           loadType: ["third-party"]),
            action: .init(type: "block")
        )
    }

    private func write(_ rules: [ContentBlockerRule], to filename: String) throws {
        let data = try JSONEncoder().encode(rules)
        try data.write(to: directory.appendingPathComponent(filename))
    }

    func test_purge_emptiesSelfRules() throws {
        try write([hostBlockRule("ads.example.com")], to: SelfReportedRulesStore.selfFilename)
        let store = SelfReportedRulesStore(directory: directory)

        XCTAssertTrue(try store.purgeSelfRules(), "自己ルールがあれば変化ありを返す")
        XCTAssertTrue(store.loadSelfRules().isEmpty)
    }

    func test_purge_keepsGlobalRulesIntact() throws {
        let global = hostBlockRule("tracker.example.net")
        try write([global], to: SelfReportedRulesStore.globalFilename)
        try write([hostBlockRule("ads.example.com")], to: SelfReportedRulesStore.selfFilename)
        let store = SelfReportedRulesStore(directory: directory)

        _ = try store.purgeSelfRules()

        XCTAssertEqual(store.loadGlobalRules(), [global], "CDN 由来の global は無傷")
        XCTAssertEqual(store.loadMergedRules(), [global], "merged は global だけで作り直される")
    }

    func test_purge_isIdempotent() throws {
        try write([hostBlockRule("ads.example.com")], to: SelfReportedRulesStore.selfFilename)
        let store = SelfReportedRulesStore(directory: directory)

        XCTAssertTrue(try store.purgeSelfRules())
        XCTAssertFalse(try store.purgeSelfRules(), "2 回目以降は変化なし（毎起動呼んでよい）")
    }

    func test_purge_onCleanDevice_reportsNoChange() throws {
        let store = SelfReportedRulesStore(directory: directory)
        XCTAssertFalse(try store.purgeSelfRules())
    }

    /// global に紛れ込んだ document 遮断ルールは merged から除外され続ける（4.0.3 の治癒を維持）。
    func test_purge_stillStripsDocumentBlockingRulesFromGlobal() throws {
        let risky = ContentBlockerRule(
            trigger: .init(urlFilter: #"^[^:]+://+([^:/]+\.)?risky\.example\.com[/:]"#),
            action: .init(type: "block")
        )
        let safe = hostBlockRule("tracker.example.net")
        try write([risky, safe], to: SelfReportedRulesStore.globalFilename)
        let store = SelfReportedRulesStore(directory: directory)

        _ = try store.purgeSelfRules()

        XCTAssertEqual(store.loadMergedRules(), [safe])
    }
}
