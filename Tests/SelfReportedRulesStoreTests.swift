import XCTest
@testable import AdblockKeshi

/// 報告由来ルールの保存層。
///
/// D-lite で自己報告ファストレーン（`rules-self.json` への追記）は廃止した。
/// 現役の供給源はサーバ検証を通った `rules-global.json` のみで、
/// このストアの仕事は「global を安全化して `rules-reported.json` を作る」ことに絞られる。
/// 残骸の掃除は `SelfReportPurgeTests` が担当する。
final class SelfReportedRulesStoreTests: XCTestCase {

    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func writeGlobal(_ rules: [ContentBlockerRule]) throws {
        try JSONEncoder().encode(rules)
            .write(to: dir.appendingPathComponent(SelfReportedRulesStore.globalFilename))
    }

    private func writeSelf(_ rules: [ContentBlockerRule]) throws {
        try JSONEncoder().encode(rules)
            .write(to: dir.appendingPathComponent(SelfReportedRulesStore.selfFilename))
    }

    /// merged のファイル名は rules-reported.json に固定（rebuildMerged が書く正準名）。
    func test_merged_filename_is_canonical() {
        XCTAssertEqual(SelfReportedRulesStore.mergedFilename, "rules-reported.json")
    }

    func test_rebuild_writes_global_rules_to_merged() throws {
        let store = SelfReportedRulesStore(directory: dir)
        let a = TestRuleFactory.hostBlockRule("a.test")
        let b = TestRuleFactory.hostBlockRule("b.test")
        try writeGlobal([a, b])

        try store.rebuildMerged()

        XCTAssertEqual(store.loadMergedRules(), [a, b])
    }

    /// purge 前の端末が起動しきるまでの過渡状態: self が残っていても内容一致で dedup される。
    func test_rebuild_dedupes_self_against_global() throws {
        let store = SelfReportedRulesStore(directory: dir)
        let a = TestRuleFactory.hostBlockRule("a.test")
        let b = TestRuleFactory.hostBlockRule("b.test")
        try writeGlobal([a, b])
        try writeSelf([a])

        try store.rebuildMerged()

        XCTAssertEqual(Set(store.loadMergedRules().map { $0.trigger.urlFilter }),
                       Set([a, b].map { $0.trigger.urlFilter }))
    }

    /// 予算超過時に末尾が優先保持されるため、並び順は global → self。
    func test_safeMerged_orders_self_last() throws {
        let store = SelfReportedRulesStore(directory: dir)
        let selfRule = TestRuleFactory.hostBlockRule("self-ad.test")
        let globalRule = TestRuleFactory.hostBlockRule("global-ad.test")
        try writeSelf([selfRule])
        try writeGlobal([globalRule])

        let safe = store.safeMergedReportedRules()

        XCTAssertTrue(safe.contains(globalRule))
        XCTAssertEqual(safe.last, selfRule)
        XCTAssertFalse(safe.contains(where: { ReportedRuleSafety.isDocumentBlockingRisk($0) }))
    }

    // MARK: - 防御多層（2026-06-23）

    /// 防御多層: CDN(global)経由で document ブロックが来ても merged に出さない。
    func test_rebuild_strips_document_blocking_global_rule() throws {
        let store = SelfReportedRulesStore(directory: dir)
        let badGlobal = TestRuleFactory.documentBlockingRule("streamtape.com")
        try writeGlobal([badGlobal])

        try store.rebuildMerged()

        XCTAssertFalse(store.loadMergedRules().contains(badGlobal))
    }

    /// merged に残った document ブロックが strip されて中身が変わるなら changed=true
    /// （起動時 migration が reload を発火させ即治癒するため）。
    func test_rebuild_reports_changed_when_merged_loses_document_block() throws {
        let store = SelfReportedRulesStore(directory: dir)
        let bad = TestRuleFactory.documentBlockingRule("streamtape.com")
        let safe = TestRuleFactory.hostBlockRule("ads.test")
        try writeGlobal([safe])
        // 旧版が書いた merged にはまだ bad が残っている状態を再現。
        try JSONEncoder().encode([safe, bad])
            .write(to: dir.appendingPathComponent(SelfReportedRulesStore.mergedFilename))

        XCTAssertTrue(try store.rebuildMerged())
        XCTAssertFalse(store.loadMergedRules().contains(bad))
        XCTAssertTrue(store.loadMergedRules().contains(safe))
    }

    /// cosmetic な global ルール(selector/if-domain)は破壊せず faithfully 保持する。
    /// L6 の cosmetic は first-party でも効く唯一の経路なので、ここを壊すと D-lite の改善が届かない。
    func test_rebuild_preserves_cosmetic_global_rule_faithfully() throws {
        let store = SelfReportedRulesStore(directory: dir)
        let css = ContentBlockerRule(
            trigger: .init(urlFilter: ".*", ifDomain: ["example.com"]),
            action: .init(type: "css-display-none", selector: ".ad")
        )
        try writeGlobal([css])

        try store.rebuildMerged()

        XCTAssertEqual(store.loadMergedRules(), [css])
    }

    /// url-filter が同一でも内容が異なる cosmetic ルール（"*" + 別 selector/domain）は
    /// 取りこぼさず両方残る（dedup は url-filter ではなくルール内容で行う）。
    func test_rebuild_keeps_distinct_cosmetic_rules_sharing_url_filter() throws {
        let store = SelfReportedRulesStore(directory: dir)
        let css1 = ContentBlockerRule(
            trigger: .init(urlFilter: ".*", ifDomain: ["a.example"]),
            action: .init(type: "css-display-none", selector: ".ad1")
        )
        let css2 = ContentBlockerRule(
            trigger: .init(urlFilter: ".*", ifDomain: ["b.example"]),
            action: .init(type: "css-display-none", selector: ".ad2")
        )
        try writeGlobal([css1, css2])

        try store.rebuildMerged()

        XCTAssertEqual(Set(store.loadMergedRules()), Set([css1, css2]))
    }
}
