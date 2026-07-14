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

    /// TCP フラグ（RST 合成の判定・検証に使う最小セット）。
    struct TCPFlags: OptionSet, Equatable {
        let rawValue: UInt8
        static let fin = TCPFlags(rawValue: 0x01)
        static let syn = TCPFlags(rawValue: 0x02)
        static let rst = TCPFlags(rawValue: 0x04)
        static let ack = TCPFlags(rawValue: 0x10)
    }

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
        /// transport ペイロード（UDP なら DNS メッセージ本体・TCP では未使用）
        let payload: Data
        /// TCP のときのみ有効（UDP は 0 / [])
        var tcpSeq: UInt32 = 0
        var tcpAck: UInt32 = 0
        var tcpFlags: TCPFlags = []
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
        case 6:
            return parseIPv6(bytes)
        default:
            return nil
        }
    }

    private static func parseIPv6(_ b: [UInt8]) -> ParsedPacket? {
        guard b.count >= 40 + 8 else { return nil }
        let nextHeader = b[6]
        guard nextHeader == 17 else { return nil }   // 17 = UDP（拡張ヘッダは非対応・来たら nil=fail-open）
        let srcIP = Data(b[8..<24])
        let dstIP = Data(b[24..<40])
        let u = 40
        let srcPort = UInt16(b[u]) << 8 | UInt16(b[u + 1])
        let dstPort = UInt16(b[u + 2]) << 8 | UInt16(b[u + 3])
        let udpLen = Int(UInt16(b[u + 4]) << 8 | UInt16(b[u + 5]))
        guard udpLen >= 8, b.count >= u + udpLen else { return nil }
        let payload = Data(b[(u + 8)..<(u + udpLen)])
        return ParsedPacket(
            version: .v6, proto: .udp,
            srcIP: srcIP, dstIP: dstIP,
            srcPort: srcPort, dstPort: dstPort, payload: payload)
    }

    /// 受信 UDP パケットへの応答を組み立てる（src/dst を入れ替え、payload を差し替え）。
    /// checksum は正しく計算する（IPv4 header checksum / IPv6 UDP 擬似ヘッダ checksum）。
    static func buildResponse(to req: ParsedPacket, payload: Data) -> Data {
        precondition(req.proto == .udp, "buildResponse: UDP のみ")
        switch req.version {
        case .v4: return buildResponseIPv4(to: req, payload: payload)
        case .v6: return buildResponseIPv6(to: req, payload: payload)
        }
    }

    private static func buildResponseIPv4(to req: ParsedPacket, payload: Data) -> Data {
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

    private static func buildResponseIPv6(to req: ParsedPacket, payload: Data) -> Data {
        let udpLen = 8 + payload.count
        let src = [UInt8](req.dstIP)   // 入れ替え
        let dst = [UInt8](req.srcIP)
        var p = [UInt8]()
        // IPv6 header (40 bytes)
        p.append(0x60)
        p.append(contentsOf: [0x00, 0x00, 0x00])
        p.append(UInt8(udpLen >> 8)); p.append(UInt8(udpLen & 0xff))
        p.append(17)                             // next header = UDP
        p.append(64)                             // hop limit
        p.append(contentsOf: src)
        p.append(contentsOf: dst)
        // UDP header（port 入れ替え）
        var udp = [UInt8]()
        udp.append(UInt8(req.dstPort >> 8)); udp.append(UInt8(req.dstPort & 0xff))
        udp.append(UInt8(req.srcPort >> 8)); udp.append(UInt8(req.srcPort & 0xff))
        udp.append(UInt8(udpLen >> 8)); udp.append(UInt8(udpLen & 0xff))
        udp.append(0); udp.append(0)             // checksum placeholder
        udp.append(contentsOf: payload)
        let ck = udpChecksumIPv6(src: src, dst: dst, udp: udp)
        udp[6] = UInt8(ck >> 8); udp[7] = UInt8(ck & 0xff)
        p.append(contentsOf: udp)
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

    /// IPv6 UDP checksum（擬似ヘッダ = src16 + dst16 + UDP長(4) + next-header(17)）。0 は 0xffff に丸める。
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
        return ck == 0 ? 0xffff : ck
    }

    private static func parseIPv4(_ b: [UInt8]) -> ParsedPacket? {
        let ihl = Int(b[0] & 0x0f)
        let headerLen = ihl * 4
        guard ihl >= 5, b.count >= headerLen + 8 else { return nil }
        let proto = b[9]
        let srcIP = Data(b[12..<16])
        let dstIP = Data(b[16..<20])
        let u = headerLen
        switch proto {
        case 17:   // UDP
            let srcPort = UInt16(b[u]) << 8 | UInt16(b[u + 1])
            let dstPort = UInt16(b[u + 2]) << 8 | UInt16(b[u + 3])
            let udpLen = Int(UInt16(b[u + 4]) << 8 | UInt16(b[u + 5]))
            guard udpLen >= 8, b.count >= u + udpLen else { return nil }
            let payload = Data(b[(u + 8)..<(u + udpLen)])
            return ParsedPacket(version: .v4, proto: .udp, srcIP: srcIP, dstIP: dstIP,
                                srcPort: srcPort, dstPort: dstPort, payload: payload)
        case 6:    // TCP（最小 parse: ports/seq/flags のみ）
            guard b.count >= u + 20 else { return nil }
            return parseTCP(b, at: u, version: .v4, srcIP: srcIP, dstIP: dstIP)
        default:
            return nil   // 非対応プロトコルは fail-open
        }
    }

    /// TCP ヘッダの最小 parse（ports/seq/ack/flags）。payload は使わないので空。
    private static func parseTCP(_ b: [UInt8], at u: Int, version: IPVersion,
                                 srcIP: Data, dstIP: Data) -> ParsedPacket? {
        let srcPort = UInt16(b[u]) << 8 | UInt16(b[u + 1])
        let dstPort = UInt16(b[u + 2]) << 8 | UInt16(b[u + 3])
        let seq = UInt32(b[u + 4]) << 24 | UInt32(b[u + 5]) << 16 | UInt32(b[u + 6]) << 8 | UInt32(b[u + 7])
        let ack = UInt32(b[u + 8]) << 24 | UInt32(b[u + 9]) << 16 | UInt32(b[u + 10]) << 8 | UInt32(b[u + 11])
        let flags = TCPFlags(rawValue: b[u + 13])
        return ParsedPacket(version: version, proto: .tcp, srcIP: srcIP, dstIP: dstIP,
                            srcPort: srcPort, dstPort: dstPort, payload: Data(),
                            tcpSeq: seq, tcpAck: ack, tcpFlags: flags)
    }

    /// TCP:53 への RST 応答を合成する（fail-fast・案A）。userspace TCP shim は作らない。
    /// RST|ACK・seq=0・ack=req.seq+1・src/dst 入れ替え。IPv4 のみ（v1 では TCP は IPv4 前提で足りる）。
    static func buildTCPRST(to req: ParsedPacket) -> Data? {
        guard req.proto == .tcp, req.version == .v4 else { return nil }
        let tcpLen = 20
        let totalLen = 20 + tcpLen
        let src = [UInt8](req.dstIP)   // 入れ替え
        let dst = [UInt8](req.srcIP)
        var p = [UInt8](repeating: 0, count: totalLen)
        // IPv4 header
        p[0] = 0x45
        p[2] = UInt8(totalLen >> 8); p[3] = UInt8(totalLen & 0xff)
        p[8] = 64; p[9] = 6   // TCP
        for i in 0..<4 { p[12 + i] = src[i]; p[16 + i] = dst[i] }
        let ipck = ipv4HeaderChecksum(Array(p[0..<20]))
        p[10] = UInt8(ipck >> 8); p[11] = UInt8(ipck & 0xff)
        // TCP header（port 入れ替え・RST|ACK）
        var t = [UInt8](repeating: 0, count: 20)
        t[0] = UInt8(req.dstPort >> 8); t[1] = UInt8(req.dstPort & 0xff)  // src = 元 dst
        t[2] = UInt8(req.srcPort >> 8); t[3] = UInt8(req.srcPort & 0xff)  // dst = 元 src
        // seq = 0
        let ackNum = req.tcpSeq &+ 1
        t[8] = UInt8(ackNum >> 24 & 0xff); t[9] = UInt8(ackNum >> 16 & 0xff)
        t[10] = UInt8(ackNum >> 8 & 0xff); t[11] = UInt8(ackNum & 0xff)
        t[12] = 0x50                                   // data offset 5
        t[13] = TCPFlags([.rst, .ack]).rawValue        // RST|ACK
        // TCP checksum（IPv4 擬似ヘッダ）
        let ck = tcpChecksumIPv4(src: src, dst: dst, tcp: t)
        t[16] = UInt8(ck >> 8); t[17] = UInt8(ck & 0xff)
        for i in 0..<20 { p[20 + i] = t[i] }
        return Data(p)
    }

    /// IPv4 TCP checksum（擬似ヘッダ = src4 + dst4 + zero + protocol(6) + TCP長(2)）。
    private static func tcpChecksumIPv4(src: [UInt8], dst: [UInt8], tcp: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        func add(_ bytes: [UInt8]) {
            var i = 0
            while i + 1 < bytes.count { sum += UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1]); i += 2 }
            if i < bytes.count { sum += UInt32(bytes[i]) << 8 }
        }
        add(src); add(dst)
        add([0, 6, UInt8(tcp.count >> 8), UInt8(tcp.count & 0xff)])
        add(tcp)
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        return UInt16(~sum & 0xffff)
    }
}
