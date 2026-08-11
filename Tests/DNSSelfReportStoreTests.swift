import XCTest
@testable import AdblockKeshi

/// DNSSelfReportStore（報告ドメインの自己ファストレーン保存・dns-self.json）のテスト。
final class DNSSelfReportStoreTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dns-self-\(UUID().uuidString).json")
    }

    func test_append_thenRead_roundTrips() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = DNSSelfReportStore(fileURL: url)
        try store.appendDomain("ads.example.com")
        XCTAssertEqual(store.readDomains(), ["ads.example.com"])
    }

    func test_append_dedupes_caseInsensitive_andTrailingDot() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = DNSSelfReportStore(fileURL: url)
        try store.appendDomain("ads.example.com")
        try store.appendDomain("ADS.Example.com.")   // 大小/末尾ドット違い = 同一
        XCTAssertEqual(store.readDomains().count, 1, "正規化して重複排除")
    }

    func test_append_multipleDistinct_accumulates() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = DNSSelfReportStore(fileURL: url)
        try store.appendDomain("a.example.com")
        try store.appendDomain("b.example.net")
        XCTAssertEqual(Set(store.readDomains()), ["a.example.com", "b.example.net"])
    }

    func test_append_ignoresEmpty() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = DNSSelfReportStore(fileURL: url)
        try store.appendDomain("   ")
        XCTAssertTrue(store.readDomains().isEmpty)
    }

    func test_read_missingFile_returnsEmpty() {
        XCTAssertTrue(DNSSelfReportStore(fileURL: tempURL()).readDomains().isEmpty)
    }

    func test_read_corruptJSON_returnsEmpty() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        XCTAssertTrue(DNSSelfReportStore(fileURL: url).readDomains().isEmpty, "不正 JSON は fail-safe 空配列")
    }

    // MARK: - purge（v4.0.3 hotfix: 自己報告ファストレーンの残骸削除）

    func test_purge_removesStoredDomains() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = DNSSelfReportStore(fileURL: url)
        try store.appendDomain("news.example.com")

        try store.purge()

        XCTAssertTrue(store.readDomains().isEmpty, "purge 後は自己報告ドメインが残らない")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "ファイル自体も残さない")
    }

    func test_purge_returnsTrue_whenFileExisted() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = DNSSelfReportStore(fileURL: url)
        try store.appendDomain("news.example.com")

        XCTAssertTrue(try store.purge(), "削除した場合は true（稼働中 tunnel の reload 要否判定に使う）")
    }

    func test_purge_missingFile_returnsFalse_andDoesNotThrow() throws {
        let store = DNSSelfReportStore(fileURL: tempURL())
        XCTAssertFalse(try store.purge(), "元から無ければ false（何もしていない）")
    }

    func test_purge_isIdempotent() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = DNSSelfReportStore(fileURL: url)
        try store.appendDomain("news.example.com")

        XCTAssertTrue(try store.purge())
        XCTAssertFalse(try store.purge(), "2 回目以降は no-op（フラグ管理を不要にする性質）")
        XCTAssertTrue(store.readDomains().isEmpty)
    }

    func test_purge_corruptFile_isAlsoRemoved() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        let store = DNSSelfReportStore(fileURL: url)

        XCTAssertTrue(try store.purge(), "壊れた JSON でも残骸として削除する")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
