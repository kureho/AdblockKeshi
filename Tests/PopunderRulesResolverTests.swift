import XCTest
@testable import AdblockKeshi

/// popunder/タップ乗っ取り対策フィルタは App Group → bundle の `popunder-rules.json` から読む。
/// ファイル名/App Group ID を間違えると拡張が空になり機能しないため、配線契約を固定する。
final class PopunderRulesResolverTests: XCTestCase {

    func test_make_uses_popunder_filename() {
        XCTAssertEqual(PopunderRulesResolver.make().filterFilename, "popunder-rules.json")
    }

    func test_make_uses_shared_app_group() {
        XCTAssertEqual(PopunderRulesResolver.make().appGroupIdentifier,
                       "group.com.kureho.adblockkeshi.shared")
    }

    func test_resolve_returns_nil_when_nothing_available() {
        let resolver = BlockerListResolver(
            appGroupIdentifier: "group.nonexistent.test",
            filterFilename: PopunderRulesResolver.filename,
            bundle: Bundle(for: type(of: self))
        )
        XCTAssertNil(resolver.resolve())
    }
}
