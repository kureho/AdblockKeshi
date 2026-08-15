import XCTest
@testable import AdblockKeshi

/// SiteExceptionsStore（「このサイトで一時オフ」のドメイン保存・site-exceptions.json）のテスト。
/// v4.2.0: 壊れ報告フローから追加し、Safari Content Blocker の per-site 例外
/// （ignore-previous-rules）の生成元になる。
/// fail-safe: 未存在 / 不正 JSON は空配列（= 例外なし・ブロックが生きる方向）。
final class SiteExceptionsStoreTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("site-exceptions-\(UUID().uuidString).json")
    }

    func test_read_missingFile_returnsEmpty() {
        XCTAssertTrue(SiteExceptionsStore(fileURL: tempURL()).readDomains().isEmpty)
    }

    func test_read_corruptJSON_returnsEmpty() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        XCTAssertTrue(SiteExceptionsStore(fileURL: url).readDomains().isEmpty)
    }

    func test_add_thenRead_roundTrips() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = SiteExceptionsStore(fileURL: url)
        try store.add("news.example.com")
        XCTAssertEqual(store.readDomains(), ["news.example.com"])
    }

    func test_add_normalizes_caseAndTrailingDot_andDedupes() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = SiteExceptionsStore(fileURL: url)
        try store.add("News.Example.com.")
        try store.add("news.example.com")
        XCTAssertEqual(store.readDomains(), ["news.example.com"], "正規化して重複排除")
    }

    func test_add_ignoresEmpty() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = SiteExceptionsStore(fileURL: url)
        try store.add("   ")
        XCTAssertTrue(store.readDomains().isEmpty)
    }

    func test_add_preservesInsertionOrder() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = SiteExceptionsStore(fileURL: url)
        try store.add("b.example.net")
        try store.add("a.example.com")
        XCTAssertEqual(store.readDomains(), ["b.example.net", "a.example.com"],
                       "追加順を保持（管理リストの表示順 = ユーザーが追加した順）")
    }

    func test_remove_deletesOnlyThatDomain() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = SiteExceptionsStore(fileURL: url)
        try store.add("a.example.com")
        try store.add("b.example.net")
        try store.remove("A.Example.com")   // 正規化してから照合
        XCTAssertEqual(store.readDomains(), ["b.example.net"])
    }

    func test_remove_lastDomain_removesFile() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = SiteExceptionsStore(fileURL: url)
        try store.add("a.example.com")
        try store.remove("a.example.com")
        XCTAssertTrue(store.readDomains().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "空になったらファイルを残さない（= 例外ゼロ判定が単純になる）")
    }

    func test_remove_unknownDomain_doesNotThrow() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = SiteExceptionsStore(fileURL: url)
        try store.add("a.example.com")
        XCTAssertNoThrow(try store.remove("unknown.example.org"))
        XCTAssertEqual(store.readDomains(), ["a.example.com"])
    }
}
