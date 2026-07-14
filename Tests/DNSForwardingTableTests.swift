import XCTest
@testable import AdblockKeshi

/// DNSForwardingTable（上流応答の突合・リライト後 DNS ID 単独キー）のテスト。
/// spec: docs/superpowers/specs/2026-07-14-v4-freemium-dns-design.md §上流転送 / plan Task 13
final class DNSForwardingTableTests: XCTestCase {

    func test_insertResolve_consumesOnce() {
        let t = DNSForwardingTable()
        let req = Self.request(srcPort: 5000, id: 0x1111)
        t.insert(rewrittenID: 0xABCD, request: req, now: 100)
        XCTAssertEqual(t.resolve(rewrittenID: 0xABCD), req)
        XCTAssertNil(t.resolve(rewrittenID: 0xABCD), "resolve は1回で消費される")
    }

    func test_distinctRewrittenIDs_areIndependent() {
        let t = DNSForwardingTable()
        let a = Self.request(srcPort: 5000, id: 0x1234)
        let b = Self.request(srcPort: 6000, id: 0x1234)   // 元 ID が同じでもリライト後 ID が別なら衝突しない
        t.insert(rewrittenID: 1, request: a, now: 100)
        t.insert(rewrittenID: 2, request: b, now: 100)
        XCTAssertEqual(t.resolve(rewrittenID: 2), b)
        XCTAssertEqual(t.resolve(rewrittenID: 1), a)
    }

    func test_contains_reflectsOutstanding() {
        let t = DNSForwardingTable()
        XCTAssertFalse(t.contains(rewrittenID: 42))
        t.insert(rewrittenID: 42, request: Self.request(srcPort: 5000, id: 1), now: 100)
        XCTAssertTrue(t.contains(rewrittenID: 42))
        _ = t.resolve(rewrittenID: 42)
        XCTAssertFalse(t.contains(rewrittenID: 42), "消費後は未使用に戻る")
    }

    func test_expireAll_removesOldEntries() {
        let t = DNSForwardingTable()
        t.insert(rewrittenID: 1, request: Self.request(srcPort: 5000, id: 1), now: 100)
        t.insert(rewrittenID: 2, request: Self.request(srcPort: 5001, id: 2), now: 200)
        t.expireAll(olderThan: 150)   // timestamp < 150 を削除
        XCTAssertNil(t.resolve(rewrittenID: 1), "古いエントリは掃除される")
        XCTAssertNotNil(t.resolve(rewrittenID: 2), "新しいエントリは残る")
    }

    func test_resolve_missingKey_returnsNil() {
        let t = DNSForwardingTable()
        XCTAssertNil(t.resolve(rewrittenID: 1))
    }

    // MARK: - Helpers

    /// 元クライアントの DNS クエリ相当の ParsedPacket（payload 先頭 2 バイト = 元 DNS ID）。
    static func request(srcPort: UInt16, id: UInt16) -> PacketCodec.ParsedPacket {
        PacketCodec.ParsedPacket(
            version: .v4, proto: .udp,
            srcIP: Data([10, 0, 0, 1]), dstIP: Data([1, 1, 1, 1]),
            srcPort: srcPort, dstPort: 53,
            payload: Data([UInt8(id >> 8), UInt8(id & 0xff)]))
    }
}
