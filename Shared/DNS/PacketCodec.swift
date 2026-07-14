import Foundation

/// DNS tunnel が扱う raw IP パケットの decode/encode（NetworkExtension 非依存の純関数）。
///
/// NEPacketTunnelProvider の `packetFlow` は IP レイヤの生パケットを渡してくるため、
/// DNS メッセージを取り出す前に IPv4/IPv6 + UDP（+ TCP:53 の最小判定）ヘッダを解く必要がある。
/// パース不能なものはすべて `nil` を返す（呼び出し側はそれを「素通し＝forward」に倒す＝fail-open の起点）。
///
/// spec: docs/superpowers/specs/2026-07-14-v4-freemium-dns-design.md §3（PacketCodec）
enum PacketCodec {

    enum IPVersion: Equatable { case v4, v6 }
    enum TransportProto: Equatable { case udp, tcp }

    /// パース済みパケット（応答合成に必要な最小情報）。
    struct ParsedPacket: Equatable {
        let version: IPVersion
        let proto: TransportProto
        /// 送信元 IP（4 or 16 バイト）
        let srcIP: Data
        /// 宛先 IP（4 or 16 バイト）
        let dstIP: Data
        let srcPort: UInt16
        let dstPort: UInt16
        /// transport ペイロード（UDP なら DNS メッセージ本体）
        let payload: Data
    }

    /// raw IP パケットを解く。IPv4/UDP のみ対応（IPv6・TCP は後続 Task で拡張）。
    /// 解けないもの・非対応プロトコルは nil（fail-open）。
    static func parse(_ packet: Data) -> ParsedPacket? {
        guard packet.count >= 20 else { return nil }
        let bytes = [UInt8](packet)
        let version = bytes[0] >> 4
        switch version {
        case 4:
            return parseIPv4(bytes)
        default:
            return nil
        }
    }

    /// 受信 UDP パケットへの応答を組み立てる（src/dst を入れ替え、payload を差し替え）。
    /// IPv4/UDP のみ（IPv6 は後続 Task）。header checksum は正しく計算する。
    static func buildResponse(to req: ParsedPacket, payload: Data) -> Data {
        precondition(req.version == .v4 && req.proto == .udp, "buildResponse: v1 は IPv4/UDP のみ")
        let udpLen = 8 + payload.count
        let totalLen = 20 + udpLen
        var p = [UInt8](repeating: 0, count: totalLen)
        // IPv4 header
        p[0] = 0x45                       // version 4, IHL 5
        p[1] = 0x00
        p[2] = UInt8(totalLen >> 8); p[3] = UInt8(totalLen & 0xff)
        p[4] = 0; p[5] = 0                // identification
        p[6] = 0; p[7] = 0                // flags/fragment
        p[8] = 64                         // TTL
        p[9] = 17                         // protocol = UDP
        p[10] = 0; p[11] = 0              // checksum placeholder
        // src = 元 dst / dst = 元 src（入れ替え）
        for i in 0..<4 { p[12 + i] = [UInt8](req.dstIP)[i] }
        for i in 0..<4 { p[16 + i] = [UInt8](req.srcIP)[i] }
        // header checksum
        let cksum = ipv4HeaderChecksum(Array(p[0..<20]))
        p[10] = UInt8(cksum >> 8); p[11] = UInt8(cksum & 0xff)
        // UDP header（port も入れ替え）
        p[20] = UInt8(req.dstPort >> 8); p[21] = UInt8(req.dstPort & 0xff)  // src port = 元 dst
        p[22] = UInt8(req.srcPort >> 8); p[23] = UInt8(req.srcPort & 0xff)  // dst port = 元 src
        p[24] = UInt8(udpLen >> 8); p[25] = UInt8(udpLen & 0xff)
        p[26] = 0; p[27] = 0              // UDP checksum 0（IPv4 では省略可）
        for (i, byte) in payload.enumerated() { p[28 + i] = byte }
        return Data(p)
    }

    /// IPv4 ヘッダ（20 バイト・checksum フィールドは 0 前提）の 1 の補数和 checksum。
    private static func ipv4HeaderChecksum(_ header: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < header.count {
            sum += UInt32(header[i]) << 8 | UInt32(header[i + 1])
            i += 2
        }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        return UInt16(~sum & 0xffff)
    }

    private static func parseIPv4(_ b: [UInt8]) -> ParsedPacket? {
        let ihl = Int(b[0] & 0x0f)
        let headerLen = ihl * 4
        guard ihl >= 5, b.count >= headerLen + 8 else { return nil }
        let proto = b[9]
        guard proto == 17 else { return nil }   // 17 = UDP（TCP は後続 Task）
        let srcIP = Data(b[12..<16])
        let dstIP = Data(b[16..<20])
        // UDP ヘッダ
        let u = headerLen
        let srcPort = UInt16(b[u]) << 8 | UInt16(b[u + 1])
        let dstPort = UInt16(b[u + 2]) << 8 | UInt16(b[u + 3])
        let udpLen = Int(UInt16(b[u + 4]) << 8 | UInt16(b[u + 5]))
        guard udpLen >= 8, b.count >= u + udpLen else { return nil }
        let payload = Data(b[(u + 8)..<(u + udpLen)])
        return ParsedPacket(
            version: .v4, proto: .udp,
            srcIP: srcIP, dstIP: dstIP,
            srcPort: srcPort, dstPort: dstPort, payload: payload)
    }
}
