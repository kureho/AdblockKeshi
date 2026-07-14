import XCTest
@testable import AdblockKeshi

/// DNS tunnel の raw IP パケット処理（NetworkExtension 非依存の純関数）のテスト。
/// spec: docs/superpowers/specs/2026-07-14-v4-freemium-dns-design.md §PacketCodec
final class PacketCodecTests: XCTestCase {

    // MARK: - Task 1: IPv4/UDP パース

    func test_parseIPv4UDP_extractsPortsAndPayload() throws {
        let payload = Data([0xAA, 0xBB, 0xCC])
        let packet = Self.makeIPv4UDP(
            src: (10, 0, 0, 1), srcPort: 5353,
            dst: (198, 18, 0, 1), dstPort: 53, payload: payload)
        let parsed = try XCTUnwrap(PacketCodec.parse(packet))
        XCTAssertEqual(parsed.version, .v4)
        XCTAssertEqual(parsed.proto, .udp)
        XCTAssertEqual(parsed.srcPort, 5353)
        XCTAssertEqual(parsed.dstPort, 53)
        XCTAssertEqual(parsed.payload, payload)
    }

    func test_parse_returnsNil_forGarbage() {
        XCTAssertNil(PacketCodec.parse(Data([0x00])))          // 短すぎ
        XCTAssertNil(PacketCodec.parse(Data()))                // 空
    }

    // MARK: - Task 2: IPv4/UDP 応答パケットの組み立て（endpoint swap + checksum）

    func test_buildResponse_swapsEndpointsAndSetsPayload() throws {
        let req = try XCTUnwrap(PacketCodec.parse(Self.makeIPv4UDP(
            src: (10, 0, 0, 1), srcPort: 5353,
            dst: (198, 18, 0, 1), dstPort: 53, payload: Data([0x01]))))
        let respPayload = Data([0x09, 0x08])
        let respPacket = PacketCodec.buildResponse(to: req, payload: respPayload)
        let parsed = try XCTUnwrap(PacketCodec.parse(respPacket))
        XCTAssertEqual(parsed.srcPort, 53)      // 応答の src は元の dst
        XCTAssertEqual(parsed.dstPort, 5353)    // 応答の dst は元の src
        XCTAssertEqual(parsed.srcIP, Data([198, 18, 0, 1]))  // src/dst IP も入れ替わる
        XCTAssertEqual(parsed.dstIP, Data([10, 0, 0, 1]))
        XCTAssertEqual(parsed.payload, respPayload)
    }

    func test_buildResponse_ipv4HeaderChecksumIsValid() throws {
        let req = try XCTUnwrap(PacketCodec.parse(Self.makeIPv4UDP(
            src: (10, 0, 0, 1), srcPort: 5353,
            dst: (198, 18, 0, 1), dstPort: 53, payload: Data([0x01]))))
        let resp = PacketCodec.buildResponse(to: req, payload: Data([0x09, 0x08]))
        // IPv4 ヘッダ 20 バイトの 16bit ワード総和（checksum 含む）は 0xFFFF になる（検証式）。
        XCTAssertTrue(Self.ipv4HeaderChecksumValid(resp))
    }

    /// IPv4 ヘッダ（先頭 IHL*4 バイト）の checksum が正しいか（16bit 1の補数和が 0xFFFF）。
    static func ipv4HeaderChecksumValid(_ packet: Data) -> Bool {
        let b = [UInt8](packet)
        guard b.count >= 20 else { return false }
        let ihl = Int(b[0] & 0x0f) * 4
        var sum: UInt32 = 0
        var i = 0
        while i < ihl {
            sum += UInt32(b[i]) << 8 | UInt32(b[i + 1])
            i += 2
        }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        return sum == 0xffff
    }

    // MARK: - Task 3: IPv6/UDP パース + 応答（擬似ヘッダ checksum 必須）

    func test_parseIPv6UDP_extractsPortsAndPayload() throws {
        let src: [UInt8] = [0xfd,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1]   // fd00::1
        let dst: [UInt8] = [0xfd,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2]   // fd00::2
        let payload = Data([0xDE, 0xAD])
        let packet = Self.makeIPv6UDP(src: src, srcPort: 5353, dst: dst, dstPort: 53, payload: payload)
        let parsed = try XCTUnwrap(PacketCodec.parse(packet))
        XCTAssertEqual(parsed.version, .v6)
        XCTAssertEqual(parsed.proto, .udp)
        XCTAssertEqual(parsed.srcPort, 5353)
        XCTAssertEqual(parsed.dstPort, 53)
        XCTAssertEqual(parsed.srcIP, Data(src))
        XCTAssertEqual(parsed.dstIP, Data(dst))
        XCTAssertEqual(parsed.payload, payload)
    }

    func test_buildResponse_ipv6_swapsEndpoints_andUDPChecksumNonZero() throws {
        let src: [UInt8] = [0xfd,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1]
        let dst: [UInt8] = [0xfd,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2]
        let req = try XCTUnwrap(PacketCodec.parse(
            Self.makeIPv6UDP(src: src, srcPort: 5353, dst: dst, dstPort: 53, payload: Data([0x01]))))
        let resp = PacketCodec.buildResponse(to: req, payload: Data([0x09, 0x08]))
        let parsed = try XCTUnwrap(PacketCodec.parse(resp))
        XCTAssertEqual(parsed.version, .v6)
        XCTAssertEqual(parsed.srcPort, 53)
        XCTAssertEqual(parsed.dstPort, 5353)
        XCTAssertEqual(parsed.srcIP, Data(dst))   // 入れ替わり
        XCTAssertEqual(parsed.dstIP, Data(src))
        // IPv6 は UDP checksum 必須（0 不可）
        let b = [UInt8](resp)
        let ck = UInt16(b[40 + 6]) << 8 | UInt16(b[40 + 7])
        XCTAssertNotEqual(ck, 0, "IPv6 では UDP checksum は 0 にできない")
    }

    // MARK: - Task 4: TCP:53 の最小 parse + RST 応答合成（fail-open 層2・案A）

    /// TCP SYN(dst 53) を parse できること + それに対する RST 応答を合成できること。
    func test_tcpSyn_parseAndBuildRST() throws {
        let syn = Self.makeIPv4TCPSyn(
            src: (10, 0, 0, 1), srcPort: 40000,
            dst: (198, 18, 0, 1), dstPort: 53, seq: 1000)
        let parsed = try XCTUnwrap(PacketCodec.parse(syn))
        XCTAssertEqual(parsed.proto, .tcp)
        XCTAssertEqual(parsed.dstPort, 53)
        XCTAssertTrue(parsed.tcpFlags.contains(.syn))
        let rst = try XCTUnwrap(PacketCodec.buildTCPRST(to: parsed))
        let prst = try XCTUnwrap(PacketCodec.parse(rst))
        XCTAssertEqual(prst.proto, .tcp)
        XCTAssertTrue(prst.tcpFlags.contains(.rst))
        XCTAssertTrue(prst.tcpFlags.contains(.ack))
        XCTAssertEqual(prst.srcPort, 53)      // RST の src は元 dst
        XCTAssertEqual(prst.dstPort, 40000)   // RST の dst は元 src
        XCTAssertEqual(prst.tcpAck, 1001)     // ack = SYN.seq + 1
        XCTAssertTrue(Self.ipv4HeaderChecksumValid(rst))
    }

    /// buildTCPRST は IPv4/TCP 以外には nil（fail-open）。
    func test_buildTCPRST_returnsNil_forNonTCP() throws {
        let udp = try XCTUnwrap(PacketCodec.parse(Self.makeIPv4UDP(
            src: (10, 0, 0, 1), srcPort: 5353,
            dst: (198, 18, 0, 1), dstPort: 53, payload: Data([0x01]))))
        XCTAssertNil(PacketCodec.buildTCPRST(to: udp))
    }

    /// 最小の IPv6 + UDP パケット（UDP checksum は擬似ヘッダで正しく計算）。
    static func makeIPv6UDP(
        src: [UInt8], srcPort: UInt16, dst: [UInt8], dstPort: UInt16, payload: Data
    ) -> Data {
        precondition(src.count == 16 && dst.count == 16)
        let udpLen = 8 + payload.count
        var p = [UInt8]()
        // IPv6 header (40 bytes)
        p.append(0x60)                          // version 6
        p.append(contentsOf: [0x00, 0x00, 0x00]) // traffic class / flow label
        p.append(UInt8(udpLen >> 8)); p.append(UInt8(udpLen & 0xff))  // payload length
        p.append(17)                            // next header = UDP
        p.append(64)                            // hop limit
        p.append(contentsOf: src)
        p.append(contentsOf: dst)
        // UDP header
        var udp = [UInt8]()
        udp.append(UInt8(srcPort >> 8)); udp.append(UInt8(srcPort & 0xff))
        udp.append(UInt8(dstPort >> 8)); udp.append(UInt8(dstPort & 0xff))
        udp.append(UInt8(udpLen >> 8)); udp.append(UInt8(udpLen & 0xff))
        udp.append(0); udp.append(0)            // checksum placeholder
        udp.append(contentsOf: payload)
        let ck = udpChecksumIPv6(src: src, dst: dst, udp: udp)
        udp[6] = UInt8(ck >> 8); udp[7] = UInt8(ck & 0xff)
        p.append(contentsOf: udp)
        return Data(p)
    }

    /// IPv6 UDP checksum（擬似ヘッダ = src16 + dst16 + length(4) + next-header(17)）。
    static func udpChecksumIPv6(src: [UInt8], dst: [UInt8], udp: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        func add(_ bytes: [UInt8]) {
            var i = 0
            while i + 1 < bytes.count { sum += UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1]); i += 2 }
            if i < bytes.count { sum += UInt32(bytes[i]) << 8 }
        }
        add(src); add(dst)
        let len = udp.count
        add([UInt8(len >> 24 & 0xff), UInt8(len >> 16 & 0xff), UInt8(len >> 8 & 0xff), UInt8(len & 0xff)])
        add([0, 0, 0, 17])
        add(udp)
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        let ck = UInt16(~sum & 0xffff)
        return ck == 0 ? 0xffff : ck   // UDP checksum 0 は「未計算」を意味するので 0xffff に
    }

    // MARK: - Helpers（手組みパケット）

    /// 最小の IPv4 + UDP パケットを手組みする（IHL=5・checksum は 0 で可＝受信側は検証しない）。
    static func makeIPv4UDP(
        src: (UInt8, UInt8, UInt8, UInt8), srcPort: UInt16,
        dst: (UInt8, UInt8, UInt8, UInt8), dstPort: UInt16,
        payload: Data
    ) -> Data {
        let udpLen = UInt16(8 + payload.count)
        let totalLen = UInt16(20 + Int(udpLen))
        var p = Data()
        // IPv4 header (20 bytes)
        p.append(0x45)                    // version 4, IHL 5
        p.append(0x00)                    // DSCP/ECN
        p.append(UInt8(totalLen >> 8)); p.append(UInt8(totalLen & 0xff))
        p.append(contentsOf: [0x00, 0x00])       // identification
        p.append(contentsOf: [0x00, 0x00])       // flags/fragment
        p.append(64)                      // TTL
        p.append(17)                      // protocol = UDP
        p.append(contentsOf: [0x00, 0x00])       // header checksum (0 = 計算省略)
        p.append(contentsOf: [src.0, src.1, src.2, src.3])
        p.append(contentsOf: [dst.0, dst.1, dst.2, dst.3])
        // UDP header (8 bytes)
        p.append(UInt8(srcPort >> 8)); p.append(UInt8(srcPort & 0xff))
        p.append(UInt8(dstPort >> 8)); p.append(UInt8(dstPort & 0xff))
        p.append(UInt8(udpLen >> 8)); p.append(UInt8(udpLen & 0xff))
        p.append(contentsOf: [0x00, 0x00])       // UDP checksum (0 = 未使用)
        p.append(payload)
        return p
    }

    /// 最小の IPv4 + TCP SYN パケット（payload 無し・IHL=5・checksum は 0 で可＝parse は検証しない）。
    static func makeIPv4TCPSyn(
        src: (UInt8, UInt8, UInt8, UInt8), srcPort: UInt16,
        dst: (UInt8, UInt8, UInt8, UInt8), dstPort: UInt16,
        seq: UInt32
    ) -> Data {
        let totalLen = UInt16(20 + 20)   // IPv4(20) + TCP(20)
        var p = Data()
        // IPv4 header (20 bytes)
        p.append(0x45)
        p.append(0x00)
        p.append(UInt8(totalLen >> 8)); p.append(UInt8(totalLen & 0xff))
        p.append(contentsOf: [0x00, 0x00])       // identification
        p.append(contentsOf: [0x00, 0x00])       // flags/fragment
        p.append(64)                      // TTL
        p.append(6)                       // protocol = TCP
        p.append(contentsOf: [0x00, 0x00])       // header checksum (0 = 計算省略)
        p.append(contentsOf: [src.0, src.1, src.2, src.3])
        p.append(contentsOf: [dst.0, dst.1, dst.2, dst.3])
        // TCP header (20 bytes)
        p.append(UInt8(srcPort >> 8)); p.append(UInt8(srcPort & 0xff))
        p.append(UInt8(dstPort >> 8)); p.append(UInt8(dstPort & 0xff))
        p.append(UInt8(seq >> 24 & 0xff)); p.append(UInt8(seq >> 16 & 0xff))
        p.append(UInt8(seq >> 8 & 0xff)); p.append(UInt8(seq & 0xff))
        p.append(contentsOf: [0x00, 0x00, 0x00, 0x00])   // ack = 0（SYN）
        p.append(0x50)                    // data offset 5, reserved
        p.append(0x02)                    // flags = SYN
        p.append(contentsOf: [0xff, 0xff])       // window
        p.append(contentsOf: [0x00, 0x00])       // checksum (0 = 未計算)
        p.append(contentsOf: [0x00, 0x00])       // urgent pointer
        return p
    }
}
