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

    func test_parseQuery_returnsNil_forMultiQuestion() {
        // QDCOUNT=2 は非対応 → nil（fail-open で forward。先頭一致で残りを落とさない）
        var d = Self.header(qdcount: 2)
        for _ in 0..<2 {
            d.append(contentsOf: [0x03, 0x61, 0x64, 0x73, 0x00])  // "ads" root
            d.append(contentsOf: [0x00, 0x01, 0x00, 0x01])         // QTYPE/QCLASS
        }
        XCTAssertNil(DNSMessage.parseQuery(d))
    }

    func test_parseQuery_returnsNil_forZeroQuestion() {
        XCTAssertNil(DNSMessage.parseQuery(Self.header(qdcount: 0)))
    }

    func test_parseQuery_returnsNil_forCompressionPointer() {
        // QNAME 先頭が圧縮ポインタ（上位2bit=11）→ クエリでは異常 → nil（fail-open）
        var d = Self.header(qdcount: 1)
        d.append(contentsOf: [0xC0, 0x0C])       // 圧縮ポインタ
        d.append(contentsOf: [0x00, 0x01, 0x00, 0x01])  // QTYPE/QCLASS
        XCTAssertNil(DNSMessage.parseQuery(d))
    }

    // MARK: - Task 6: block 応答の合成（qtype 別）

    func test_buildBlockResponse_A_returnsZeroIP() throws {
        let q = try XCTUnwrap(DNSMessage.parseQuery(Self.makeQuery(qname: "ads.example.com", qtype: 1)))
        let resp = DNSMessage.buildBlockResponse(for: q)
        let b = [UInt8](resp)
        XCTAssertEqual(UInt16(b[0]) << 8 | UInt16(b[1]), Self.expectedID)   // id コピー
        XCTAssertEqual(b[2] & 0x80, 0x80)                                   // QR=1
        XCTAssertEqual(b[3] & 0x0f, 0)                                      // RCODE=NOERROR
        XCTAssertEqual(UInt16(b[4]) << 8 | UInt16(b[5]), 1)                 // QDCOUNT=1
        XCTAssertEqual(UInt16(b[6]) << 8 | UInt16(b[7]), 1)                 // ANCOUNT=1
        XCTAssertTrue(Self.answerRDATAIsAllZero(resp, expectedRDLen: 4))    // 0.0.0.0
    }

    func test_buildBlockResponse_AAAA_returnsZeroIPv6() throws {
        let q = try XCTUnwrap(DNSMessage.parseQuery(Self.makeQuery(qname: "ads.example.com", qtype: 28)))
        let resp = DNSMessage.buildBlockResponse(for: q)
        let b = [UInt8](resp)
        XCTAssertEqual(UInt16(b[6]) << 8 | UInt16(b[7]), 1)                 // ANCOUNT=1
        XCTAssertTrue(Self.answerRDATAIsAllZero(resp, expectedRDLen: 16))   // ::
    }

    func test_buildBlockResponse_HTTPS_returnsNODATA() throws {
        let q = try XCTUnwrap(DNSMessage.parseQuery(Self.makeQuery(qname: "ads.example.com", qtype: 65)))
        let resp = DNSMessage.buildBlockResponse(for: q)
        let b = [UInt8](resp)
        XCTAssertEqual(b[2] & 0x80, 0x80)                                   // QR=1
        XCTAssertEqual(b[3] & 0x0f, 0)                                      // RCODE=NOERROR（NXDOMAIN ではない）
        XCTAssertEqual(UInt16(b[4]) << 8 | UInt16(b[5]), 1)                 // QDCOUNT=1（qd 保持）
        XCTAssertEqual(UInt16(b[6]) << 8 | UInt16(b[7]), 0)                 // ANCOUNT=0（NODATA）
    }

    /// answer セクションの RDATA が全ゼロ（0.0.0.0 / ::）で長さが期待通りかを検証。
    static func answerRDATAIsAllZero(_ resp: Data, expectedRDLen: Int) -> Bool {
        let b = [UInt8](resp)
        let ans = questionEndOffset(b)              // answer セクション先頭
        // NAME(2) + TYPE(2) + CLASS(2) + TTL(4) + RDLENGTH(2) = 12 バイト後に RDATA
        guard b.count >= ans + 12 else { return false }
        let rdlen = Int(UInt16(b[ans + 10]) << 8 | UInt16(b[ans + 11]))
        guard rdlen == expectedRDLen, b.count >= ans + 12 + rdlen else { return false }
        return b[(ans + 12)..<(ans + 12 + rdlen)].allSatisfy { $0 == 0 }
    }

    /// question セクション末尾（= answer 先頭）のオフセットを求める。
    static func questionEndOffset(_ b: [UInt8]) -> Int {
        var i = 12
        while i < b.count { let len = Int(b[i]); i += 1; if len == 0 { break }; i += len }
        return i + 4   // + QTYPE + QCLASS
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
