import XCTest
@testable import AdblockKeshi

/// A-88 §3・進め方1: 送信成功時にサーバーの報告 ID (`server_id`) を履歴へ保存できるようにする。
/// 既存端末には `server_id` を持たない行が残っているため、
/// フィールド無しの古い JSON も引き続きデコードできること（fail-safe を崩さない）を固定する。
final class ReportHistoryItemServerIdTests: XCTestCase {

    private func makeItem(serverId: String?) -> ReportHistoryItem {
        ReportHistoryItem(
            id: "local-1", url: "https://example.com/a", memo: nil, memoRedacted: false,
            status: .pending, createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            validatedAt: nil, appliedAt: nil, serverId: serverId
        )
    }

    func test_serverId_roundTripsThroughJSON() throws {
        let item = makeItem(serverId: "5b1e6f2a-1234-4a11-9c22-0000000000aa")
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ReportHistoryItem.self, from: data)
        XCTAssertEqual(decoded.serverId, "5b1e6f2a-1234-4a11-9c22-0000000000aa")
    }

    func test_serverId_defaultsToNil_whenOmittedFromInit() {
        let item = ReportHistoryItem(
            id: "local-2", url: "https://example.com/b", memo: nil, memoRedacted: false,
            status: .pending, createdAt: Date(), validatedAt: nil, appliedAt: nil
        )
        XCTAssertNil(item.serverId)
    }

    /// 4.3 以前に保存された行には `server_id` キー自体が存在しない。
    func test_legacyJSONWithoutServerIdKey_decodesWithNilServerId() throws {
        let legacy = Data("""
        {"id":"1","url":"https://ads.example.com/a","memo_redacted":false,
        "status":"pending","created_at":1785542400}
        """.utf8)
        let decoded = try JSONDecoder().decode(ReportHistoryItem.self, from: legacy)
        XCTAssertNil(decoded.serverId)
        XCTAssertEqual(decoded.id, "1")
    }
}
