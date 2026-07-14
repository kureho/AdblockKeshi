import Foundation

/// 上流(1.1.1.1 等)へ転送したクエリの「元クライアント宛パケット」を保持し、
/// 上流応答が来たときに正しい相手へ配送するための対応表。
/// キーは srcPort + DNS transaction ID の複合（ID 単独だと別アプリの同一 ID と衝突し誤配送する）。
/// tunnel の I/O から切り離した純ロジック（時刻は呼び出し側から注入）。
/// spec: docs/superpowers/specs/2026-07-14-v4-freemium-dns-design.md §上流転送
final class DNSForwardingTable {

    struct Key: Hashable {
        let srcPort: UInt16
        let transactionID: UInt16
    }

    private struct Entry {
        let packet: Data
        let timestamp: TimeInterval
    }

    private var entries: [Key: Entry] = [:]

    var count: Int { entries.count }

    /// 転送したクエリの元パケットを登録する（now = 登録時刻）。
    func insert(srcPort: UInt16, id: UInt16, packet: Data, now: TimeInterval) {
        entries[Key(srcPort: srcPort, transactionID: id)] = Entry(packet: packet, timestamp: now)
    }

    /// 上流応答に対応する元パケットを取り出す。取り出したら消費する（1回限り）。
    func resolve(srcPort: UInt16, id: UInt16) -> Data? {
        let key = Key(srcPort: srcPort, transactionID: id)
        guard let entry = entries.removeValue(forKey: key) else { return nil }
        return entry.packet
    }

    /// cutoff より古い（timestamp < cutoff）エントリを掃除する。
    func expireAll(olderThan cutoff: TimeInterval) {
        entries = entries.filter { $0.value.timestamp >= cutoff }
    }
}
