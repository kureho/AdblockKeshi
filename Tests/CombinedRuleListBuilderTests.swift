import XCTest
@testable import AdblockKeshi

/// combined-<variant> の生成・change-guard・last-known-good。
final class CombinedRuleListBuilderTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func block(_ host: String) -> ContentBlockerRule {
        ContentBlockerRule(trigger: .init(urlFilter: "^https?://\(host)/"), action: .init(type: "block"))
    }
    private func writeStandard(_ rules: [ContentBlockerRule], _ name: String) throws -> URL {
        let u = dir.appendingPathComponent(name)
        try JSONEncoder().encode(rules).write(to: u)
        return u
    }
    private func combinedRules(_ variant: String) throws -> [ContentBlockerRule] {
        let u = dir.appendingPathComponent(CombinedRuleListBuilder.combinedFilename(forVariant: variant))
        return try JSONDecoder().decode([ContentBlockerRule].self, from: Data(contentsOf: u))
    }

    func test_rebuild_creates_combined_with_standard_then_reported() throws {
        let std = try writeStandard([block("a.test"), block("b.test")], "merged-rules.json")
        let b = CombinedRuleListBuilder(directory: dir, appBuildVersion: "100")
        let out = try b.rebuildIfNeeded(variantFilename: "merged-rules.json", standardRulesURL: std,
                                        mayTruncate: false, reportedSafe: [block("c.test")])
        XCTAssertTrue(out.rebuilt)
        XCTAssertEqual(try combinedRules("merged-rules.json"),
                       [block("a.test"), block("b.test"), block("c.test")])
    }

    func test_change_guard_skips_when_inputs_unchanged() throws {
        let std = try writeStandard([block("a.test")], "merged-rules.json")
        let b = CombinedRuleListBuilder(directory: dir, appBuildVersion: "100")
        XCTAssertTrue(try b.rebuildIfNeeded(variantFilename: "merged-rules.json", standardRulesURL: std,
                                            mayTruncate: false, reportedSafe: [block("c.test")]).rebuilt)
        // 同一入力 → 再生成しない
        XCTAssertFalse(try b.rebuildIfNeeded(variantFilename: "merged-rules.json", standardRulesURL: std,
                                             mayTruncate: false, reportedSafe: [block("c.test")]).rebuilt)
    }

    func test_change_guard_rebuilds_when_reported_changes() throws {
        let std = try writeStandard([block("a.test")], "merged-rules.json")
        let b = CombinedRuleListBuilder(directory: dir, appBuildVersion: "100")
        _ = try b.rebuildIfNeeded(variantFilename: "merged-rules.json", standardRulesURL: std,
                                  mayTruncate: false, reportedSafe: [block("c.test")])
        let out = try b.rebuildIfNeeded(variantFilename: "merged-rules.json", standardRulesURL: std,
                                        mayTruncate: false, reportedSafe: [block("c.test"), block("d.test")])
        XCTAssertTrue(out.rebuilt)
        XCTAssertEqual(try combinedRules("merged-rules.json").count, 3)
    }

    func test_change_guard_rebuilds_when_app_version_changes() throws {
        let std = try writeStandard([block("a.test")], "merged-rules.json")
        _ = try CombinedRuleListBuilder(directory: dir, appBuildVersion: "100")
            .rebuildIfNeeded(variantFilename: "merged-rules.json", standardRulesURL: std,
                             mayTruncate: false, reportedSafe: [block("c.test")])
        let out = try CombinedRuleListBuilder(directory: dir, appBuildVersion: "101")
            .rebuildIfNeeded(variantFilename: "merged-rules.json", standardRulesURL: std,
                             mayTruncate: false, reportedSafe: [block("c.test")])
        XCTAssertTrue(out.rebuilt)
    }


    private func combinedExists(_ variant: String) -> Bool {
        FileManager.default.fileExists(atPath:
            dir.appendingPathComponent(CombinedRuleListBuilder.combinedFilename(forVariant: variant)).path)
    }

    /// 自己学習が空なら combined を書かない（19.5MB の標準複製を作らない＝disk 肥大回避）。
    /// resolver は combined 不在時に bundle 標準へフォールバックする（reported 無し時はそれが正しい）。
    func test_empty_reported_writes_no_combined() throws {
        let std = try writeStandard([block("a.test"), block("b.test")], "merged-rules.json")
        let b = CombinedRuleListBuilder(directory: dir, appBuildVersion: "100")
        let out = try b.rebuildIfNeeded(variantFilename: "merged-rules.json", standardRulesURL: std,
                                        mayTruncate: false, reportedSafe: [])
        XCTAssertFalse(out.rebuilt)               // 書く対象なし
        XCTAssertFalse(combinedExists("merged-rules.json")) // combined 不在
    }

    /// 自己学習が空になったら（migration purge 等）既存 combined を削除し、bundle 標準へ戻す。
    func test_empty_reported_removes_stale_combined() throws {
        let std = try writeStandard([block("a.test")], "merged-rules.json")
        let b = CombinedRuleListBuilder(directory: dir, appBuildVersion: "100")
        // 一度 reported ありで生成 → combined 存在
        _ = try b.rebuildIfNeeded(variantFilename: "merged-rules.json", standardRulesURL: std,
                                  mayTruncate: false, reportedSafe: [block("c.test")])
        XCTAssertTrue(combinedExists("merged-rules.json"))
        // reported 空 → stale combined を削除して reload を促す
        let out = try b.rebuildIfNeeded(variantFilename: "merged-rules.json", standardRulesURL: std,
                                        mayTruncate: false, reportedSafe: [])
        XCTAssertTrue(out.rebuilt)                // 削除＝変化あり → reload
        XCTAssertFalse(combinedExists("merged-rules.json"))
    }

    /// compile-verify が throw したら install せず、既存 combined（last-known-good）を保持する。
    func test_compile_verify_failure_keeps_last_known_good() throws {
        let std = try writeStandard([block("a.test")], "merged-rules.json")
        let b = CombinedRuleListBuilder(directory: dir, appBuildVersion: "100")
        // 1回目: 正常 install
        _ = try b.rebuildIfNeeded(variantFilename: "merged-rules.json", standardRulesURL: std,
                                  mayTruncate: false, reportedSafe: [block("c.test")])
        let good = try combinedRules("merged-rules.json")
        // 2回目: reported 変更だが compile-verify が失敗
        struct CompileFail: Error {}
        XCTAssertThrowsError(try b.rebuildIfNeeded(variantFilename: "merged-rules.json", standardRulesURL: std,
                                                   mayTruncate: false, reportedSafe: [block("c.test"), block("d.test")],
                                                   compileVerify: { _ in throw CompileFail() }))
        // 既存 combined は不変（治癒失敗で壊れた状態を固定しない）
        XCTAssertEqual(try combinedRules("merged-rules.json"), good)
    }

    /// base 内容が変わったら（CDN で popunder base が更新された等）combined を再生成する。
    /// change-key に base 内容ハッシュを含めるため検知できる（CDN 更新が stale combined にマスクされない）。
    func test_change_guard_rebuilds_when_base_content_changes() throws {
        let std = try writeStandard([block("a.test")], "popunder-rules.json")
        let b = CombinedRuleListBuilder(directory: dir, appBuildVersion: "100")
        _ = try b.rebuildIfNeeded(variantFilename: "popunder-rules.json", standardRulesURL: std,
                                  mayTruncate: false, reportedSafe: [block("c.test")])
        // base を更新（CDN 更新相当）
        _ = try writeStandard([block("a.test"), block("b.test")], "popunder-rules.json")
        let out = try b.rebuildIfNeeded(variantFilename: "popunder-rules.json", standardRulesURL: std,
                                        mayTruncate: false, reportedSafe: [block("c.test")])
        XCTAssertTrue(out.rebuilt, "base 内容変更で再生成されるべき")
        XCTAssertEqual(try combinedRules("popunder-rules.json").count, 3)
    }

    /// 非アクティブ variant の combined は cleanup で削除（disk 肥大回避）。
    func test_cleanup_removes_non_active_variant_combined() throws {
        let b = CombinedRuleListBuilder(directory: dir, appBuildVersion: "100")
        let mStd = try writeStandard([block("a.test")], "merged-rules.json")
        let aStd = try writeStandard([block("b.test")], "ad-rules.json")
        _ = try b.rebuildIfNeeded(variantFilename: "merged-rules.json", standardRulesURL: mStd,
                                  mayTruncate: false, reportedSafe: [block("c.test")])
        _ = try b.rebuildIfNeeded(variantFilename: "ad-rules.json", standardRulesURL: aStd,
                                  mayTruncate: true, reportedSafe: [block("c.test")])
        XCTAssertTrue(combinedExists("merged-rules.json"))
        XCTAssertTrue(combinedExists("ad-rules.json"))
        b.cleanupCombined(except: "merged-rules.json")
        XCTAssertTrue(combinedExists("merged-rules.json"))   // アクティブは残る
        XCTAssertFalse(combinedExists("ad-rules.json"))      // 非アクティブは削除
    }

    /// mayTruncate 経路（小入力では truncation 起きず prefix+reported）。truncation 算術は ReportedRuleBudgetTests が担保。
    func test_truncate_path_small_input_no_truncation() throws {
        let std = try writeStandard((0..<5).map { block("s\($0).test") }, "ad-rules.json")
        let b = CombinedRuleListBuilder(directory: dir, appBuildVersion: "100")
        let out = try b.rebuildIfNeeded(variantFilename: "ad-rules.json", standardRulesURL: std,
                                        mayTruncate: true, reportedSafe: [block("r.test")])
        XCTAssertTrue(out.rebuilt)
        XCTAssertEqual(try combinedRules("ad-rules.json").count, 6)
        XCTAssertEqual(out.droppedStandard, 0)
    }
}
