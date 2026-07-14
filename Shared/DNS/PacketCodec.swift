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
