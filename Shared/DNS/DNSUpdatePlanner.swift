import Foundation

/// DNS リスト self-fetch の更新要否を判定する純ロジック（tunnel の I/O から分離）。
/// 手元の適用済み sha（applied-dns 記録）と CDN の version-dns.json manifest を比較する。
enum DNSUpdatePlanner {

    /// version-dns.json の manifest（build_dns_rules.py が出力する形）。
    struct Manifest: Decodable, Equatable {
        let sha256: String
        let bytes: Int
        enum CodingKeys: String, CodingKey {
            case sha256 = "dns-rules_sha256"
            case bytes = "dns-rules_bytes"
        }
    }

    /// version-dns.json を parse する（不正は nil）。
    static func parseManifest(_ data: Data) -> Manifest? {
        try? JSONDecoder().decode(Manifest.self, from: data)
    }

    /// 手元 sha と CDN manifest を比較し、更新が要るか。手元が無い/異なれば要更新。
    static func needsUpdate(localSHA: String?, remote: Manifest) -> Bool {
        localSHA != remote.sha256
    }
}
