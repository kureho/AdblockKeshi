import Foundation

/// 上流(1.1.1.1 等)へ転送したクエリの「元クライアントのリクエスト」を保持し、
/// 上流応答が来たときに正しい相手へ配送するための対応表。
///
/// キー = **リライト後の DNS transaction ID 単独**。
/// 上流は共有 NWConnection なので応答には DNS ID しか載らず、元クライアントの srcPort/srcIP は
/// 復元できない。そこで tunnel は転送前に DNS ID をユニーク値へリライトし、その値をキーにして
/// 元 request（srcIP/srcPort/元 DNS ID を含む ParsedPacket）を引く。応答時に元 ID へ戻して合成する。
/// ID リライトで一意化するため、別クライアントの同一 ID 衝突は構造的に消える。
///
/// tunnel の I/O から切り離した純ロジック（時刻・リライト後 ID は呼び出し側から注入）。
/// spec: docs/superpowers/specs/2026-07-14-v4-freemium-dns-design.md §上流転送 / plan Task 13
final class DNSForwardingTable {

    struct Entry: Equatable {
        /// 元クライアントのクエリパケット（srcIP/srcPort と元 DNS ID を保持）。応答合成の材料。
        let request: PacketCodec.ParsedPacket
        let timestamp: TimeInterval
    }

    private var entries: [UInt16: Entry] = [:]

    var count: Int { entries.count }

    /// あるリライト後 ID が使用中か（tunnel の ID 割り当てが未使用値を選ぶために参照）。
    func contains(rewrittenID: UInt16) -> Bool {
        entries[rewrittenID] != nil
    }

    /// 転送したクエリの元 request を登録する（rewrittenID = リライト後 ID・now = 登録時刻）。
    func insert(rewrittenID: UInt16, request: PacketCodec.ParsedPacket, now: TimeInterval) {
        entries[rewrittenID] = Entry(request: request, timestamp: now)
    }

    /// 上流応答（DNS ID = rewrittenID）に対応する元 request を取り出す。取り出したら消費する（1回限り）。
    func resolve(rewrittenID: UInt16) -> PacketCodec.ParsedPacket? {
        guard let entry = entries.removeValue(forKey: rewrittenID) else { return nil }
        return entry.request
    }

    /// cutoff より古い（timestamp < cutoff）エントリを掃除する（応答なしは偽装せず捨てる）。
    func expireAll(olderThan cutoff: TimeInterval) {
        entries = entries.filter { $0.value.timestamp >= cutoff }
    }
}
