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

    // MARK: - 統合(4→3): combined-<variant> 優先

    /// App Group の `containerURL` を temp dir に差し替えるテスト用 FileManager。
    private final class MockContainerFileManager: FileManager {
        let container: URL
        init(container: URL) { self.container = container; super.init() }
        override func containerURL(forSecurityApplicationGroupIdentifier id: String) -> URL? { container }
    }

    func test_resolve_for_state_prefers_combined_when_present() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fm = MockContainerFileManager(container: dir)
        let resolver = BlockerListResolver(appGroupIdentifier: "group.test",
                                           bundle: Bundle(for: type(of: self)), fileManager: fm)
        let state = BlockerTogglesState.default
        let variant = resolver.filename(for: state)
        // combined と 標準 variant の両方を置く → combined が優先される
        let combined = dir.appendingPathComponent("combined-" + variant)
        try Data("[]".utf8).write(to: combined)
        try Data("[]".utf8).write(to: dir.appendingPathComponent(variant))
        XCTAssertEqual(resolver.resolve(for: state), combined)
    }

    func test_resolve_for_state_falls_back_to_variant_when_no_combined() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fm = MockContainerFileManager(container: dir)
        let resolver = BlockerListResolver(appGroupIdentifier: "group.test",
                                           bundle: Bundle(for: type(of: self)), fileManager: fm)
        let state = BlockerTogglesState.default
        let variant = resolver.filename(for: state)
        let variantURL = dir.appendingPathComponent(variant)
        try Data("[]".utf8).write(to: variantURL)   // combined は無し
        XCTAssertEqual(resolver.resolve(for: state), variantURL)
    }

    // MARK: - 報告反映(popunder): resolve()（非state）の combined 優先

    func test_resolve_prefers_combined_popunder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fm = MockContainerFileManager(container: dir)
        let resolver = BlockerListResolver(appGroupIdentifier: "group.test",
                                           filterFilename: "popunder-rules.json",
                                           bundle: Bundle(for: type(of: self)), fileManager: fm)
        let combined = dir.appendingPathComponent("combined-popunder-rules.json")
        try Data("[]".utf8).write(to: combined)
        try Data("[]".utf8).write(to: dir.appendingPathComponent("popunder-rules.json"))
        XCTAssertEqual(resolver.resolve(), combined)
    }

    func test_resolve_falls_back_to_direct_when_no_combined_popunder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fm = MockContainerFileManager(container: dir)
        let resolver = BlockerListResolver(appGroupIdentifier: "group.test",
                                           filterFilename: "popunder-rules.json",
                                           bundle: Bundle(for: type(of: self)), fileManager: fm)
        let direct = dir.appendingPathComponent("popunder-rules.json")
        try Data("[]".utf8).write(to: direct)   // combined 無し → 直 App Group ファイル
        XCTAssertEqual(resolver.resolve(), direct)
    }

    /// P2 回帰防止（両トグルOFF が効かない）: empty variant は App Group の stale/CDN "[]" を返さず
    /// bundle の有効 no-op へ解決する。App Group "[]" を返すと Safari が空配列 compile を拒否し OFF が効かない。
    func test_resolve_for_empty_state_ignores_stale_appgroup_empty_array() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fm = MockContainerFileManager(container: dir)
        let resolver = BlockerListResolver(appGroupIdentifier: "group.test",
                                           bundle: Bundle(for: type(of: self)), fileManager: fm)
        let emptyState = BlockerTogglesState(adEnabled: false, securityEnabled: false)
        XCTAssertEqual(resolver.filename(for: emptyState), "empty-rules.json")
        // 旧 CDN/RuleUpdater が App Group に書いた stale "[]"
        let stale = dir.appendingPathComponent("empty-rules.json")
        try Data("[]".utf8).write(to: stale)
        // resolve は stale "[]" を返さない（bundle no-op or nil）＝OFF が確実に効く
        XCTAssertNotEqual(resolver.resolve(for: emptyState), stale)
    }
}
