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

    /// v4.2.0 の反証レビューで判明: 例外は combined 生成時に ReportedRuleBudget（予約 2,000 件）
    /// の対象に入るため、無制限に積むと古い例外が silently drop され「管理画面には停止中と
    /// 出ているのにブロックが効く」不整合になる。store 側で上限を持ち、実体と表示を一致させる。
    func test_add_keepsOnlyMostRecentUpToCap() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = SiteExceptionsStore(fileURL: url)
        let cap = SiteExceptionsStore.maxDomains
        for i in 0..<(cap + 5) {
            try store.add("example\(i).test")
        }
        let domains = store.readDomains()
        XCTAssertEqual(domains.count, cap, "上限を超えて保存しない")
        XCTAssertEqual(domains.first, "example5.test", "古い方から落ちる")
        XCTAssertEqual(domains.last, "example\(cap + 4).test", "最新は必ず残る")
    }

}
