import XCTest
@testable import AdblockKeshi

/// 報告から反映された「学習フィルタ」は App Group の rules-reported.json から読む。
/// ファイル名や App Group ID を間違えると、報告が永久に端末へ反映されない silent failure に
/// なるため、その配線契約をテストで固定する（標準側 BlockerListResolverTests と同じ思想）。
final class ReportedRulesResolverTests: XCTestCase {

    func test_make_uses_rules_reported_filename() {
        let resolver = ReportedRulesResolver.make()
        XCTAssertEqual(resolver.filterFilename, "rules-reported.json")
    }

    func test_make_uses_shared_app_group() {
        let resolver = ReportedRulesResolver.make()
        XCTAssertEqual(resolver.appGroupIdentifier, "group.com.kureho.adblockkeshi.shared")
    }

    /// App Group も bundle も該当ファイルが無ければ nil（標準側と同じフォールバック構造）。
    func test_resolve_returns_nil_when_nothing_available() {
        let testBundle = Bundle(for: type(of: self))
        let resolver = BlockerListResolver(
            appGroupIdentifier: "group.nonexistent.test",
            filterFilename: ReportedRulesResolver.filename,
            bundle: testBundle
        )
        XCTAssertNil(resolver.resolve())
    }
}
