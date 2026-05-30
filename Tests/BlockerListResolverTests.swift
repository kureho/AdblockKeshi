import XCTest
@testable import AdblockKeshi

final class BlockerListResolverTests: XCTestCase {

    func test_default_app_group_identifier() {
        let resolver = BlockerListResolver()
        XCTAssertEqual(resolver.appGroupIdentifier, "group.com.kureho.adblockkeshi.shared")
    }

    func test_default_filter_filename() {
        let resolver = BlockerListResolver()
        XCTAssertEqual(resolver.filterFilename, "blockerList.json")
    }

    func test_custom_identifier_and_filename() {
        let resolver = BlockerListResolver(
            appGroupIdentifier: "group.test.id",
            filterFilename: "custom.json"
        )
        XCTAssertEqual(resolver.appGroupIdentifier, "group.test.id")
        XCTAssertEqual(resolver.filterFilename, "custom.json")
    }

    /// App target の bundle には blockerList.json は含まれない（Extension にしかない）。
    /// テスト bundle 経由で resolve() を呼ぶと、App Group も Bundle も miss して nil を返すはず。
    func test_resolve_returns_nil_when_no_file_available() {
        let testBundle = Bundle(for: type(of: self))
        let resolver = BlockerListResolver(
            appGroupIdentifier: "group.nonexistent.test",
            filterFilename: "nonexistent-blockerList.json",
            bundle: testBundle
        )
        XCTAssertNil(resolver.resolve())
    }

    func test_bundleURL_uses_basename_and_extension() {
        let testBundle = Bundle(for: type(of: self))
        let resolver = BlockerListResolver(
            filterFilename: "anything.json",
            bundle: testBundle
        )
        // テスト bundle に anything.json は存在しないので nil
        XCTAssertNil(resolver.bundleURL())
    }
}
