import Foundation

/// 報告された広告ドメインの自己ファストレーン保存層（App Group・`dns-self.json`）。
/// 既存 Content Blocker の `rules-self.json` と対称: 「自分の報告は自分の端末で即効く」を
/// DNS ブロックでも実現する。tunnel が curated リストと union して読む（DNSBlocklistLoader）。
///
/// fail-safe: 未存在/不正 JSON は空配列（curated のみで縮退・ブロックが壊れない方向）。
struct DNSSelfReportStore {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// App Group container の dns-self.json を指す convenience initializer。
    static func sharedAppGroup(
        identifier: String = "group.com.kureho.adblockkeshi.shared"
    ) -> DNSSelfReportStore? {
        guard let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: identifier)
        else { return nil }
        return DNSSelfReportStore(fileURL: container.appendingPathComponent("dns-self.json"))
    }

    /// 保存済みの自己報告ドメイン（未存在/不正は空配列）。
    func readDomains() -> [String] {
        guard let data = try? Data(contentsOf: fileURL),
              let domains = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return domains
    }

    /// ドメインを1件追記する（小文字化・末尾ドット除去・重複排除・atomic）。空文字は無視。
    func appendDomain(_ domain: String) throws {
        let normalized = Self.normalize(domain)
        guard !normalized.isEmpty else { return }
        var domains = readDomains()
        guard !domains.contains(normalized) else { return }   // 正規化後の重複は追記しない
        domains.append(normalized)
        let data = try JSONEncoder().encode(domains)
        try data.write(to: fileURL, options: [.atomic])
    }

    /// 保存済みの自己報告ドメインを丸ごと削除する（v4.0.3 hotfix）。
    ///
    /// DNS には first-party / third-party の区別が無いため、「広告が消えなかったページ」として
    /// 報告された host をブロックすると、そのサイト自体が名前解決できなくなる（= サイトが開けない）。
    /// 自己報告ファストレーンごと廃止したので、既存端末に残っている残骸をここで消す。
    ///
    /// 戻り値: 実際に削除したら true / 元から無ければ false。idempotent なので
    /// 「一度きり」の管理フラグは不要（2 回目以降は no-op）。
    @discardableResult
    func purge() throws -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return false }
        try fileManager.removeItem(at: fileURL)
        return true
    }

    /// 小文字化 + 前後空白除去 + 末尾ドット除去（DNSBlocklist.normalize と同じ正規化）。
    private static func normalize(_ s: String) -> String {
        var d = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if d.hasSuffix(".") { d.removeLast() }
        return d
    }
}
