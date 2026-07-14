import XCTest
@testable import AdblockKeshi

/// DNSSelfReportApplier（報告URL→DNS自己リスト反映）のテスト。
final class DNSSelfReportApplierTests: XCTestCase {

    private func tempStore() -> (DNSSelfReportStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dns-self-\(UUID().uuidString).json")
        return (DNSSelfReportStore(fileURL: url), url)
    }

    func test_apply_appendsExtractedDomain() {
        let (store, url) = tempStore(); defer { try? FileManager.default.removeItem(at: url) }
        DNSSelfReportApplier(store: store).apply(reportedURL: URL(string: "https://Ads.BadNet.jp/x?y=1")!)
        XCTAssertEqual(store.readDomains(), ["ads.badnet.jp"], "報告ドメインが自己リストに入る")
    }

    func test_apply_ignoresCritical() {
        let (store, url) = tempStore(); defer { try? FileManager.default.removeItem(at: url) }
        DNSSelfReportApplier(store: store).apply(reportedURL: URL(string: "https://push.apple.com/x")!)
        XCTAssertTrue(store.readDomains().isEmpty, "critical は自己リストに入れない")
    }

    func test_apply_isIdempotentForSameDomain() {
        let (store, url) = tempStore(); defer { try? FileManager.default.removeItem(at: url) }
        let applier = DNSSelfReportApplier(store: store)
        applier.apply(reportedURL: URL(string: "https://ads.badnet.jp/a")!)
        applier.apply(reportedURL: URL(string: "https://ads.badnet.jp/b")!)   // 同一 host
        XCTAssertEqual(store.readDomains().count, 1, "同一 host は重複しない")
    }
}
