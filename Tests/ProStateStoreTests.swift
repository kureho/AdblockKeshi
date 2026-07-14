import XCTest
@testable import AdblockKeshi

/// ProStateStore（App Group への Pro 状態 atomic 書出・fail-safe 非Pro）のテスト。
final class ProStateStoreTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pro-state-\(UUID().uuidString).json")
    }

    func test_write_thenRead_roundTrips() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProStateStore(stateFileURL: url)
        try store.write(ProState(isPro: true))
        XCTAssertTrue(store.read().isPro)
    }

    func test_read_missingFile_returnsNonPro() {
        let store = ProStateStore(stateFileURL: tempURL())   // 未作成
        XCTAssertFalse(store.read().isPro, "未存在は fail-safe 非Pro")
    }

    func test_read_corruptJSON_returnsNonPro() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        let store = ProStateStore(stateFileURL: url)
        XCTAssertFalse(store.read().isPro, "不正 JSON は fail-safe 非Pro")
    }

    func test_write_false_isReadBackAsNonPro() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProStateStore(stateFileURL: url)
        try store.write(ProState(isPro: false))
        XCTAssertFalse(store.read().isPro)
    }
}
