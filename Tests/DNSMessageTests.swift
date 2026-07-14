import XCTest
@testable import AdblockKeshi

/// DNS メッセージの parse／応答合成（NetworkExtension 非依存の純関数）のテスト。
/// spec: docs/superpowers/specs/2026-07-14-v4-freemium-dns-design.md §DNSMessage
final class DNSMessageTests: XCTestCase {

    static let expectedID: UInt16 = 0x1234

    // MARK: - Task 5: question から qname/qtype を抽出

    func test_parseQuestion_extractsQNameAndType() throws {
        // "ads.example.com" A クエリの DNS メッセージを手組み
        let msg = Self.makeQuery(qname: "ads.example.com", qtype: 1) // 1 = A
        let parsed = try XCTUnwrap(DNSMessage.parseQuery(msg))
        XCTAssertEqual(parsed.qname, "ads.example.com")
        XCTAssertEqual(parsed.qtype, 1)
        XCTAssertEqual(parsed.qclass, 1)
        XCTAssertEqual(parsed.id, Self.expectedID)
    }

    func test_parseQuery_returnsNil_forGarbage() {
        XCTAssertNil(DNSMessage.parseQuery(Data([0x00, 0x01])))   // ヘッダ未満
        XCTAssertNil(DNSMessage.parseQuery(Data()))               // 空
    }

    func test_parseQuery_returnsNil_forCompressionPointer() {
        // QNAME 先頭が圧縮ポインタ（上位2bit=11）→ クエリでは異常 → nil（fail-open）
        var d = Self.header(qdcount: 1)
        d.append(contentsOf: [0xC0, 0x0C])       // 圧縮ポインタ
        d.append(contentsOf: [0x00, 0x01, 0x00, 0x01])  // QTYPE/QCLASS
        XCTAssertNil(DNSMessage.parseQuery(d))
    }

    // MARK: - Helpers（手組み DNS クエリ）

    /// DNS ヘッダ 12 バイト（ID=expectedID・標準クエリ・RD）。
    static func header(qdcount: UInt16) -> Data {
        var d = Data()
        d.append(UInt8(expectedID >> 8)); d.append(UInt8(expectedID & 0xff))
        d.append(contentsOf: [0x01, 0x00])                      // flags: standard query, RD
        d.append(UInt8(qdcount >> 8)); d.append(UInt8(qdcount & 0xff))  // QDCOUNT
        d.append(contentsOf: [0x00, 0x00])                      // ANCOUNT
        d.append(contentsOf: [0x00, 0x00])                      // NSCOUNT
        d.append(contentsOf: [0x00, 0x00])                      // ARCOUNT
        return d
    }

    /// "ads.example.com" 等の A/AAAA クエリを手組み（QCLASS=IN 固定）。
    static func makeQuery(qname: String, qtype: UInt16) -> Data {
        var d = header(qdcount: 1)
        for label in qname.split(separator: ".") {
            let bytes = Array(label.utf8)
            d.append(UInt8(bytes.count))
            d.append(contentsOf: bytes)
        }
        d.append(0x00)                                          // root ラベル
        d.append(UInt8(qtype >> 8)); d.append(UInt8(qtype & 0xff))   // QTYPE
        d.append(contentsOf: [0x00, 0x01])                     // QCLASS = IN
        return d
    }
}
