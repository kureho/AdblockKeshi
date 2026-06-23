import XCTest
@testable import AdblockKeshi

/// 報告ルールを報告反映(popunder)へ再配置する経路の回帰防止。
final class PopunderCombinedReallocationTests: XCTestCase {

    /// 【PR#30 regression 再発防止】報告反映の combined を App の coordinator が生成するため、
    /// popunder base(`popunder-rules.json`) が **App 本体バンドル(.main)** から解決できること。
    /// PR#30 は標準 22MB variant を .main から読もうとして nil → combined 未生成で reported が届かなかった。
    /// popunder base は 8KB で App にも同梱しており、ここが non-nil であることをテストで固定する。
    func test_app_main_bundle_resolves_popunder_base() throws {
        let resolver = BlockerListResolver(filterFilename: "popunder-rules.json")
        let url = try XCTUnwrap(resolver.resolveDirect(),
                                "popunder-rules.json が App 本体バンドルに同梱されていない（coordinator が base を読めない）")
        // 実際に decode できる（壊れていない）ことも確認
        let rules = try JSONDecoder().decode([ContentBlockerRule].self, from: Data(contentsOf: url))
        XCTAssertGreaterThan(rules.count, 0, "popunder base が空")
    }

    /// 基本保護の旧 combined を一掃し（bundle variant へ戻す）、popunder の combined は残す。
    func test_removeBasicCombined_clears_basic_keeps_popunder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func write(_ name: String) throws {
            try Data("[]".utf8).write(to: dir.appendingPathComponent(name))
        }
        try write("combined-merged-rules.json")
        try write("combined-ad-rules.json")
        try write("combined-popunder-rules.json") // これは残すべき
        let b = CombinedRuleListBuilder(directory: dir, appBuildVersion: "100")

        XCTAssertTrue(b.removeBasicCombined(), "basic combined があったので true")

        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("combined-merged-rules.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("combined-ad-rules.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("combined-popunder-rules.json").path),
                      "popunder の combined は basic 一掃で消さない")
        // 冪等: もう basic combined は無いので false
        XCTAssertFalse(b.removeBasicCombined())
    }
}
