import XCTest
@testable import AdblockKeshi

/// DNSEngine（判定集約・fail-open 3層）のテスト。
/// spec: docs/superpowers/specs/2026-07-14-v4-freemium-dns-design.md §DNSEngine
final class DNSEngineTests: XCTestCase {

    func test_decide_blocksListed_forwardsOthers_protectsCritical_failsOpen() throws {
        let blocklist = DNSBlocklist(domains: ["ads.example.com"])
        let engine = DNSEngine(blocklist: blocklist)

        // ブロック対象 → respond（0.0.0.0）
        let blocked = engine.decide(query: Self.query("ads.example.com", type: 1))
        guard case .respond(let data) = blocked else { return XCTFail("should block") }
        XCTAssertTrue(Self.answerIsZeroIP(data))

        // 非対象 → forward
        if case .forward = engine.decide(query: Self.query("example.com", type: 1)) {} else { XCTFail("should forward") }

        // critical はリストにあっても forward（層3）
        let g = DNSEngine(blocklist: DNSBlocklist(domains: ["push.apple.com"]))
        if case .forward = g.decide(query: Self.query("push.apple.com", type: 1)) {} else { XCTFail("critical must forward") }

        // パース不能 → forward（層1 fail-open）
        if case .forward = engine.decideRaw(Data([0x00])) {} else { XCTFail("unparsable must forward") }
    }

    func test_decideRaw_blocksListedDomain() throws {
        let engine = DNSEngine(blocklist: DNSBlocklist(domains: ["ads.example.com"]))
        let wire = Self.wireQuery("ads.example.com", type: 1)
        if case .respond = engine.decideRaw(wire) {} else { XCTFail("decideRaw should block listed domain") }
    }

    // MARK: - Helpers

    static func query(_ qname: String, type: UInt16) -> DNSMessage.Query {
        return DNSMessage.parseQuery(wireQuery(qname, type: type))!
    }

    /// 手組み DNS クエリ（ID=0x1234・標準クエリ・QCLASS=IN）。
    static func wireQuery(_ qname: String, type: UInt16) -> Data {
        var d = Data([0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        for label in qname.split(separator: ".") {
            let bytes = Array(label.utf8)
            d.append(UInt8(bytes.count)); d.append(contentsOf: bytes)
        }
        d.append(0x00)
        d.append(UInt8(type >> 8)); d.append(UInt8(type & 0xff))
        d.append(contentsOf: [0x00, 0x01])
        return d
    }

    /// ブロック応答の answer RDATA が全ゼロ（0.0.0.0 等）か。
    static func answerIsZeroIP(_ resp: Data) -> Bool {
        let b = [UInt8](resp)
        guard b.count >= 8 else { return false }
        let ancount = Int(UInt16(b[6]) << 8 | UInt16(b[7]))
        guard ancount >= 1 else { return false }
        var i = 12
        while i < b.count { let len = Int(b[i]); i += 1; if len == 0 { break }; i += len }
        i += 4   // QTYPE + QCLASS
        guard b.count >= i + 12 else { return false }
        let rdlen = Int(UInt16(b[i + 10]) << 8 | UInt16(b[i + 11]))
        guard rdlen > 0, b.count >= i + 12 + rdlen else { return false }
        return b[(i + 12)..<(i + 12 + rdlen)].allSatisfy { $0 == 0 }
    }
}
