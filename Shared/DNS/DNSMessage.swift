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

    /// ブロック応答を合成する（qtype 別）。
    /// A(1)→0.0.0.0 / AAAA(28)→:: / HTTPS(65)・SVCB(64)・その他→NODATA（RCODE=NOERROR・ANCOUNT=0）。
    /// 応答は元 id を保持・QR=1・question をそのままコピー。
    static func buildBlockResponse(for query: Query) -> Data {
        let hasAnswer = (query.qtype == 1 || query.qtype == 28)   // A / AAAA のみ address を返す
        var d = Data()
        // ヘッダ 12 バイト
        d.append(UInt8(query.id >> 8)); d.append(UInt8(query.id & 0xff))
        d.append(0x81); d.append(0x80)                     // QR=1・RD=1・RA=1・RCODE=NOERROR
        d.append(0x00); d.append(0x01)                     // QDCOUNT=1
        d.append(0x00); d.append(hasAnswer ? 0x01 : 0x00)  // ANCOUNT
        d.append(0x00); d.append(0x00)                     // NSCOUNT
        d.append(0x00); d.append(0x00)                     // ARCOUNT
        // question（qd をコピー）
        d.append(query.questionBytes)
        // answer（A/AAAA のみ・それ以外は NODATA で answer なし）
        if hasAnswer {
            d.append(contentsOf: [0xC0, 0x0C])             // NAME = 圧縮ポインタ→question の QNAME（offset 12）
            d.append(UInt8(query.qtype >> 8)); d.append(UInt8(query.qtype & 0xff))   // TYPE
            d.append(0x00); d.append(0x01)                 // CLASS=IN
            d.append(contentsOf: blockTTL)                 // TTL
            if query.qtype == 1 {
                d.append(0x00); d.append(0x04)             // RDLENGTH=4
                d.append(contentsOf: [UInt8](repeating: 0, count: 4))   // 0.0.0.0
            } else {
                d.append(0x00); d.append(0x10)             // RDLENGTH=16
                d.append(contentsOf: [UInt8](repeating: 0, count: 16))  // ::
            }
        }
        return d
    }

    /// ブロック応答の TTL（秒）。リスト更新後の復帰を早めるため短め（60 秒）。
    private static let blockTTL: [UInt8] = [0x00, 0x00, 0x00, 0x3C]
}
