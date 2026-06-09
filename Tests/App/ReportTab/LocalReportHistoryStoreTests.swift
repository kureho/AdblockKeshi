import XCTest
@testable import AdblockKeshi

@MainActor
final class LocalReportHistoryStoreTests: XCTestCase {

    private func makeStore(suiteName: String = UUID().uuidString) -> (LocalReportHistoryStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (LocalReportHistoryStore(defaults: defaults), defaults)
    }

    func test_initiallyEmpty() {
        let (store, _) = makeStore()
        XCTAssertTrue(store.items.isEmpty)
    }

    func test_append_addsItemToFront() throws {
        let (store, _) = makeStore()
        store.append(url: URL(string: "https://example.com/1")!, memo: nil)
        store.append(url: URL(string: "https://example.com/2")!, memo: "メモ")
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.first?.url, "https://example.com/2", "新しい行は先頭")
        XCTAssertEqual(store.items.first?.memo, "メモ")
        XCTAssertEqual(store.items.first?.status, .pending)
        XCTAssertFalse(store.items.first?.memoRedacted ?? true)
    }

    func test_delete_byOffsets_removesEntries() {
        let (store, _) = makeStore()
        store.append(url: URL(string: "https://a.example.com")!, memo: nil)
        store.append(url: URL(string: "https://b.example.com")!, memo: nil)
        store.append(url: URL(string: "https://c.example.com")!, memo: nil)
        // 順序: c, b, a。index 1 (= b) を削除。
        store.delete(at: IndexSet(integer: 1))
        XCTAssertEqual(store.items.map(\.url), ["https://c.example.com", "https://a.example.com"])
    }

    func test_delete_byId_removesMatchingEntry() {
        let (store, _) = makeStore()
        store.append(url: URL(string: "https://x.example.com")!, memo: nil)
        let id = store.items.first!.id
        store.delete(id: id)
        XCTAssertTrue(store.items.isEmpty)
    }

    func test_persistsAcrossInstances() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let first = LocalReportHistoryStore(defaults: defaults)
        first.append(url: URL(string: "https://persist.example.com")!, memo: "保存テスト")
        XCTAssertEqual(first.items.count, 1)

        let second = LocalReportHistoryStore(defaults: defaults)
        XCTAssertEqual(second.items.count, 1)
        XCTAssertEqual(second.items.first?.url, "https://persist.example.com")
        XCTAssertEqual(second.items.first?.memo, "保存テスト")
    }
}
