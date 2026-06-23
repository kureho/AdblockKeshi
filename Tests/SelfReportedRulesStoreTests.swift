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

    /// 自己学習 merged のファイル名は rules-reported.json に固定（rebuildMerged が書く正準名）。
    func test_merged_filename_is_canonical() {
        XCTAssertEqual(SelfReportedRulesStore.mergedFilename, "rules-reported.json")
    }

    /// round-trip: ReportedRuleBuilder 生成ルールは安全(document非遮断)なので safeMerged を生き残り、
    /// 予算超過時に self が優先されるよう順序は global → self（self が末尾）。
    func test_safeMerged_keeps_generated_rules_and_orders_self_last() throws {
        let store = SelfReportedRulesStore(directory: dir)
        let selfRule = try XCTUnwrap(ReportedRuleBuilder.blockRule(forURL: "https://self-ad.test/"))
        let globalRule = try XCTUnwrap(ReportedRuleBuilder.blockRule(forURL: "https://global-ad.test/"))
        try JSONEncoder().encode([selfRule]).write(to: dir.appendingPathComponent("rules-self.json"))
        try JSONEncoder().encode([globalRule]).write(to: dir.appendingPathComponent("rules-global.json"))

        let safe = store.safeMergedReportedRules()
        XCTAssertTrue(safe.contains(selfRule), "生成ルール(self)は安全なので残る")
        XCTAssertTrue(safe.contains(globalRule))
        XCTAssertFalse(safe.contains(where: { ReportedRuleSafety.isDocumentBlockingRisk($0) }))
        XCTAssertEqual(safe.last, selfRule, "予算超過時に優先保持されるよう self は末尾")
    }

    // MARK: - 2026-06-23 既存端末治癒 + 防御多層

    /// 旧版で生成された document ブロックの自己報告ルールが rules-self.json に残っていても、
    /// sanitize 後は self/merged から消え、ページが開けるようになる。安全な広告ルールは保持。
    func test_sanitize_purges_legacy_document_blocking_self_rule() throws {
        let store = SelfReportedRulesStore(directory: dir)
        let legacy = ContentBlockerRule(
            trigger: .init(urlFilter: #"^[^:]+://+([^:/]+\.)?streamtape\.com[/:]"#),
            action: .init(type: "block")
        )
        let safe = try XCTUnwrap(ReportedRuleBuilder.blockRule(forURL: "https://ads.test/"))
        try JSONEncoder().encode([legacy, safe]).write(to: dir.appendingPathComponent("rules-self.json"))

        let changed = try store.sanitizeStoredSelfRules()

        XCTAssertTrue(changed)
        XCTAssertFalse(store.loadSelfRules().contains(legacy), "旧 document ブロックは self から除去")
        XCTAssertTrue(store.loadSelfRules().contains(safe), "安全な広告ルールは保持")
        XCTAssertFalse(store.loadMergedRules().contains(legacy), "merged からも消える")
        XCTAssertTrue(store.loadMergedRules().contains(safe))
    }

    /// sanitize は idempotent: 危険ルールが無ければ changed=false。
    func test_sanitize_is_idempotent_when_clean() throws {
        let store = SelfReportedRulesStore(directory: dir)
        let safe = try XCTUnwrap(ReportedRuleBuilder.blockRule(forURL: "https://ads.test/"))
        XCTAssertTrue(try store.appendSelfRule(safe))
        XCTAssertFalse(try store.sanitizeStoredSelfRules())
    }

    /// self は綺麗でも、merged に残った document ブロック(global 由来など)が strip されて
    /// merged の中身が変わるなら changed=true を返す（起動時 migration が reload を発火させ即治癒するため）。
    func test_sanitize_reports_changed_when_only_merged_loses_document_block() throws {
        let store = SelfReportedRulesStore(directory: dir)
        let bad = ContentBlockerRule(
            trigger: .init(urlFilter: #"^[^:]+://+([^:/]+\.)?streamtape\.com[/:]"#),
            action: .init(type: "block")
        )
        let safe = try XCTUnwrap(ReportedRuleBuilder.blockRule(forURL: "https://ads.test/"))
        // self は安全のみ。global に危険ルール。旧版が書いた merged にはまだ bad が残っている状態を再現。
        try JSONEncoder().encode([safe]).write(to: dir.appendingPathComponent("rules-self.json"))
        try JSONEncoder().encode([bad]).write(to: dir.appendingPathComponent("rules-global.json"))
        try JSONEncoder().encode([safe, bad]).write(to: dir.appendingPathComponent("rules-reported.json"))

        let changed = try store.sanitizeStoredSelfRules()

        XCTAssertTrue(changed, "merged から危険ルールが消えるなら reload を促すため changed=true")
        XCTAssertFalse(store.loadMergedRules().contains(bad))
        XCTAssertTrue(store.loadMergedRules().contains(safe))
    }

    /// 防御多層: CDN(global)経由で document ブロックが来ても merged に出さない。
    func test_rebuild_strips_document_blocking_global_rule() throws {
        let store = SelfReportedRulesStore(directory: dir)
        let badGlobal = ContentBlockerRule(
            trigger: .init(urlFilter: #"^[^:]+://+([^:/]+\.)?streamtape\.com[/:]"#),
            action: .init(type: "block")
        )
        try JSONEncoder().encode([badGlobal]).write(to: dir.appendingPathComponent("rules-global.json"))
        try store.rebuildMerged()
        XCTAssertFalse(store.loadMergedRules().contains(badGlobal))
    }

    /// cosmetic な global ルール(selector/if-domain)は破壊せず faithfully 保持する。
    func test_rebuild_preserves_cosmetic_global_rule_faithfully() throws {
        let store = SelfReportedRulesStore(directory: dir)
        let css = ContentBlockerRule(
            trigger: .init(urlFilter: ".*", ifDomain: ["example.com"]),
            action: .init(type: "css-display-none", selector: ".ad")
        )
        try JSONEncoder().encode([css]).write(to: dir.appendingPathComponent("rules-global.json"))
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
        try JSONEncoder().encode([css1, css2]).write(to: dir.appendingPathComponent("rules-global.json"))
        try store.rebuildMerged()
        XCTAssertEqual(Set(store.loadMergedRules()), Set([css1, css2]))
    }
}
