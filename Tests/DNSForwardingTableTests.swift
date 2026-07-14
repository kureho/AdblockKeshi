import XCTest
@testable import AdblockKeshi

/// DNSForwardingTable（上流応答の突合・srcPort+ID キー）のテスト。
/// spec: docs/superpowers/specs/2026-07-14-v4-freemium-dns-design.md §上流転送
final class DNSForwardingTableTests: XCTestCase {

    func test_insertResolve_consumesOnce() {
        let t = DNSForwardingTable()
        t.insert(srcPort: 5000, id: 0x1234, packet: Data([0xAA, 0xBB]), now: 100)
        XCTAssertEqual(t.resolve(srcPort: 5000, id: 0x1234), Data([0xAA, 0xBB]))
        XCTAssertNil(t.resolve(srcPort: 5000, id: 0x1234), "resolve は1回で消費される")
    }

    func test_sameID_differentSrcPort_doNotCollide() {
        let t = DNSForwardingTable()
        t.insert(srcPort: 5000, id: 0x1234, packet: Data([0x01]), now: 100)
        t.insert(srcPort: 6000, id: 0x1234, packet: Data([0x02]), now: 100)
        XCTAssertEqual(t.resolve(srcPort: 6000, id: 0x1234), Data([0x02]))
        XCTAssertEqual(t.resolve(srcPort: 5000, id: 0x1234), Data([0x01]))
    }

    func test_expireAll_removesOldEntries() {
        let t = DNSForwardingTable()
        t.insert(srcPort: 5000, id: 1, packet: Data([0x01]), now: 100)
        t.insert(srcPort: 5001, id: 2, packet: Data([0x02]), now: 200)
        t.expireAll(olderThan: 150)   // timestamp < 150 を削除
        XCTAssertNil(t.resolve(srcPort: 5000, id: 1), "古いエントリは掃除される")
        XCTAssertEqual(t.resolve(srcPort: 5001, id: 2), Data([0x02]), "新しいエントリは残る")
    }

    func test_resolve_missingKey_returnsNil() {
        let t = DNSForwardingTable()
        XCTAssertNil(t.resolve(srcPort: 1, id: 1))
    }
}
