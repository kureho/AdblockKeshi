import Foundation

/// DNS メッセージ（クエリ）の最小パーサ／応答合成。
/// NetworkExtension 非依存の純関数群。tunnel はこの判定結果だけを使う。
/// spec: docs/superpowers/specs/2026-07-14-v4-freemium-dns-design.md §DNSMessage
enum DNSMessage {

    /// 解いた DNS クエリ（question は 1 件前提・複数や圧縮ポインタは nil=fail-open）。
    struct Query: Equatable {
        /// transaction ID（応答でそのまま返す）
        let id: UInt16
        /// 問い合わせドメイン（ラベルを "." で連結・末尾ドットなし）
        let qname: String
        /// QTYPE（1=A / 28=AAAA / 65=HTTPS / 64=SVCB ...）
        let qtype: UInt16
        /// QCLASS（通常 1=IN）
        let qclass: UInt16
        /// question セクションの生バイト（応答で qd をそのままコピーするため保持）
        let questionBytes: Data
    }

    /// raw DNS クエリを解く。解けないものは nil（fail-open で素通しさせる）。
    static func parseQuery(_ data: Data) -> Query? {
        let b = [UInt8](data)
        guard b.count >= 12 else { return nil }
        let id = UInt16(b[0]) << 8 | UInt16(b[1])
        let qdcount = UInt16(b[4]) << 8 | UInt16(b[5])
        guard qdcount >= 1 else { return nil }

        // QNAME のラベル列を decode（先頭 = header 直後の 12 バイト目）
        var i = 12
        var labels: [String] = []
        while i < b.count {
            let len = Int(b[i])
            if len == 0 { i += 1; break }            // root ラベルで終端
            if len & 0xC0 != 0 { return nil }        // 圧縮ポインタ = クエリでは異常 → fail-open
            i += 1
            guard i + len <= b.count else { return nil }
            guard let label = String(bytes: b[i..<(i + len)], encoding: .utf8) else { return nil }
            labels.append(label)
            i += len
        }
        // QNAME 直後に QTYPE(2) + QCLASS(2)
        guard i + 4 <= b.count else { return nil }
        let qtype = UInt16(b[i]) << 8 | UInt16(b[i + 1])
        let qclass = UInt16(b[i + 2]) << 8 | UInt16(b[i + 3])
        let questionBytes = Data(b[12..<(i + 4)])
        return Query(id: id, qname: labels.joined(separator: "."),
                     qtype: qtype, qclass: qclass, questionBytes: questionBytes)
    }
}
