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
}
