import XCTest
@testable import AdblockKeshi

/// BlocklistStore（App Group → bundle → 空 のロード順）のテスト。
final class BlocklistStoreTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("bl-\(UUID().uuidString).json")
    }

    private func write(_ domains: [String], to url: URL) throws {
        try JSONEncoder().encode(domains).write(to: url)
    }

    func test_loadsFromAppGroup_whenPresent() throws {
        let ag = tempURL(); let bd = tempURL()
        defer { try? FileManager.default.removeItem(at: ag); try? FileManager.default.removeItem(at: bd) }
        try write(["ag.example.com"], to: ag)
        try write(["bundle.example.com"], to: bd)
        let store = BlocklistStore(appGroupFileURL: ag, bundleFileURL: bd)
        XCTAssertEqual(store.loadDomains(), ["ag.example.com"], "App Group が最優先")
    }

    func test_fallsBackToBundle_whenAppGroupMissing() throws {
        let bd = tempURL(); defer { try? FileManager.default.removeItem(at: bd) }
        try write(["bundle.example.com"], to: bd)
        let store = BlocklistStore(appGroupFileURL: tempURL(), bundleFileURL: bd)   // App Group 未作成
        XCTAssertEqual(store.loadDomains(), ["bundle.example.com"])
    }

    func test_fallsBackToBundle_whenAppGroupEmpty() throws {
        let ag = tempURL(); let bd = tempURL()
        defer { try? FileManager.default.removeItem(at: ag); try? FileManager.default.removeItem(at: bd) }
        try write([], to: ag)                    // 空配列は bundle を隠さない
        try write(["bundle.example.com"], to: bd)
        let store = BlocklistStore(appGroupFileURL: ag, bundleFileURL: bd)
        XCTAssertEqual(store.loadDomains(), ["bundle.example.com"], "空 App Group は curated を隠さない")
    }

    func test_fallsBackToBundle_whenAppGroupCorrupt() throws {
        let ag = tempURL(); let bd = tempURL()
        defer { try? FileManager.default.removeItem(at: ag); try? FileManager.default.removeItem(at: bd) }
        try Data("not json".utf8).write(to: ag)
        try write(["bundle.example.com"], to: bd)
        let store = BlocklistStore(appGroupFileURL: ag, bundleFileURL: bd)
        XCTAssertEqual(store.loadDomains(), ["bundle.example.com"])
    }

    func test_returnsEmpty_whenBothMissing() {
        let store = BlocklistStore(appGroupFileURL: tempURL(), bundleFileURL: tempURL())
        XCTAssertTrue(store.loadDomains().isEmpty, "両方無ければ空（fail-open で forward）")
    }
}
