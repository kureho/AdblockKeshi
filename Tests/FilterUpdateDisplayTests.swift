import XCTest
@testable import AdblockKeshi

/// 「フィルタ最終更新」表示の実態化テスト。
/// 表示日付 = 実際に端末へ適用された variant の generated_at。
/// CDN 未取得端末（適用記録なし）は bundle 同梱ルールの生成日にフォールバックする。
final class FilterUpdateDisplayTests: XCTestCase {

    private let appliedDate = Date(timeIntervalSince1970: 1_782_000_000)
    private let bundleDate = Date(timeIntervalSince1970: 1_770_000_000)

    private func record(generatedAt: Date) -> AppliedRulesRecord {
        AppliedRulesRecord(
            sha256: "sha", generatedAt: generatedAt, ruleCount: 1000, appliedAt: Date())
    }

    func test_uses_applied_record_of_current_state_variant() {
        // 両トグル ON → merged-rules.json の適用記録を見る
        let date = FilterUpdateDisplay.displayDate(
            state: BlockerTogglesState(adEnabled: true, securityEnabled: true),
            applied: ["merged-rules.json": record(generatedAt: appliedDate)],
            bundledGeneratedAt: bundleDate
        )
        XCTAssertEqual(date, appliedDate)
    }

    func test_falls_back_to_bundle_date_when_no_applied_record() {
        let date = FilterUpdateDisplay.displayDate(
            state: BlockerTogglesState(adEnabled: true, securityEnabled: true),
            applied: [:],
            bundledGeneratedAt: bundleDate
        )
        XCTAssertEqual(date, bundleDate)
    }

    func test_other_variant_record_does_not_leak_into_current_state() {
        // 広告のみ ON（= ad-rules.json）なのに merged の記録しか無い → bundle 日付
        let date = FilterUpdateDisplay.displayDate(
            state: BlockerTogglesState(adEnabled: true, securityEnabled: false),
            applied: ["merged-rules.json": record(generatedAt: appliedDate)],
            bundledGeneratedAt: bundleDate
        )
        XCTAssertEqual(date, bundleDate)
    }

    func test_security_only_state_uses_security_variant_record() {
        let date = FilterUpdateDisplay.displayDate(
            state: BlockerTogglesState(adEnabled: false, securityEnabled: true),
            applied: ["security-rules.json": record(generatedAt: appliedDate)],
            bundledGeneratedAt: bundleDate
        )
        XCTAssertEqual(date, appliedDate)
    }

    func test_returns_nil_when_nothing_known() {
        let date = FilterUpdateDisplay.displayDate(
            state: BlockerTogglesState(adEnabled: true, securityEnabled: true),
            applied: [:],
            bundledGeneratedAt: nil
        )
        XCTAssertNil(date)
    }

    // MARK: - BundledRulesInfo（bundle 同梱ルールの生成日）

    func test_bundled_rules_info_decodes_generated_at() {
        let data = Data(#"{"generated_at": "2026-06-02T11:37:20Z"}"#.utf8)
        let date = BundledRulesInfo.decode(data)
        let formatter = ISO8601DateFormatter()
        XCTAssertEqual(date, formatter.date(from: "2026-06-02T11:37:20Z"))
    }

    func test_bundled_rules_info_nil_on_broken_payload() {
        XCTAssertNil(BundledRulesInfo.decode(Data("broken".utf8)))
        XCTAssertNil(BundledRulesInfo.decode(Data(#"{"generated_at": "not-a-date"}"#.utf8)))
    }

    func test_app_bundle_contains_bundled_rules_info_matching_extension_resources() throws {
        // App bundle に bundled-rules-info.json が同梱され、同梱ルール（2026-06-02 commit 8e001a2d）
        // の生成日を返すこと。ルール差し替え時はこのファイルも更新する運用。
        let date = try XCTUnwrap(BundledRulesInfo.generatedAt(bundle: .main))
        let formatter = ISO8601DateFormatter()
        XCTAssertEqual(date, formatter.date(from: "2026-06-02T11:37:20Z"))
    }
}
