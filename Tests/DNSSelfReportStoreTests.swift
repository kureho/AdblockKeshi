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
}
