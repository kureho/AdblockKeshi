import Foundation

/// 「このサイトで一時オフ」の対象ドメイン保存（App Group・`site-exceptions.json`）。
///
/// v4.2.0: 壊れ報告（Safari）の送信後に追加でき、Safari Content Blocker の
/// per-site 例外（`SiteExceptionRules` が ignore-previous-rules を生成）の唯一の入力源。
/// DNS 側には影響しない（DNS はサイト文脈を持たないため per-site 除外は原理的に不可）。
///
/// fail-safe: 未存在 / 不正 JSON は空配列（= 例外なし・ブロックが生きる方向）。
struct SiteExceptionsStore {
    static let filename = "site-exceptions.json"

    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// App Group container の site-exceptions.json を指す convenience initializer。
    static func sharedAppGroup(
        identifier: String = "group.com.kureho.adblockkeshi.shared"
    ) -> SiteExceptionsStore? {
        guard let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: identifier)
        else { return nil }
        return SiteExceptionsStore(fileURL: container.appendingPathComponent(filename))
    }

    /// 保存済みドメイン（追加順・未存在/不正は空配列）。
    func readDomains() -> [String] {
        guard let data = try? Data(contentsOf: fileURL),
              let domains = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return domains
    }

    /// ドメインを1件追加する（小文字化・末尾ドット除去・重複排除・atomic）。空文字は無視。
    func add(_ domain: String) throws {
        let normalized = Self.normalize(domain)
        guard !normalized.isEmpty else { return }
        var domains = readDomains()
        guard !domains.contains(normalized) else { return }
        domains.append(normalized)
        try write(domains)
    }

    /// ドメインを1件削除する（正規化して照合・冪等）。空になったらファイルごと消す。
    func remove(_ domain: String) throws {
        let normalized = Self.normalize(domain)
        var domains = readDomains()
        domains.removeAll { $0 == normalized }
        if domains.isEmpty {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        } else {
            try write(domains)
        }
    }

    private func write(_ domains: [String]) throws {
        let data = try JSONEncoder().encode(domains)
        try data.write(to: fileURL, options: [.atomic])
    }

    /// 小文字化 + 前後空白除去 + 末尾ドット除去（DNSBlocklist.normalize と同じ正規化）。
    private static func normalize(_ s: String) -> String {
        var d = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if d.hasSuffix(".") { d.removeLast() }
        return d
    }
}
