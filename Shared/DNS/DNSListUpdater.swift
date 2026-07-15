import Foundation
import CryptoKit

/// DNS リストの CDN 更新（self-fetch）。app 起動/BGTask（Task 14.5）と tunnel 内（Task 14）の共通ロジック。
/// version-dns.json で更新要否を判定（DNSUpdatePlanner）→ dns-rules.json 取得 → **sha256 検証** →
/// JSON 配列検証 → App Group へ atomic write + 適用 sha を記録（二重 DL 回避）。
/// ネットワークは `fetch` closure で注入（URLProtocol 不要でテスト可能）。
struct DNSListUpdater {
    let manifestURL: URL          // CDN version-dns.json
    let rulesURL: URL             // CDN dns-rules.json
    let appGroupRulesURL: URL     // 書き込み先（App Group dns-rules.json）
    let appliedRecordURL: URL     // 適用済み sha 記録（applied-dns.json）
    let fetch: (URL) async throws -> Data

    /// 本番配線（既存 CDN = GitHub Pages + App Group + URLSession）。
    static func shared(
        appGroupIdentifier: String = "group.com.kureho.adblockkeshi.shared",
        session: URLSession = .shared
    ) -> DNSListUpdater? {
        guard let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else { return nil }
        let cdnBase = URL(string: "https://kureho.github.io/AdblockKeshi/cdn/")!
        return DNSListUpdater(
            manifestURL: cdnBase.appendingPathComponent("version-dns.json"),
            rulesURL: cdnBase.appendingPathComponent("dns-rules.json"),
            appGroupRulesURL: container.appendingPathComponent("dns-rules.json"),
            appliedRecordURL: container.appendingPathComponent("applied-dns.json"),
            fetch: { url in
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                return data
            })
    }

    /// 更新が要れば取得・検証・適用する。適用したら true。
    @discardableResult
    func updateIfNeeded() async -> Bool {
        // 1. manifest を取得し、適用済み sha と比較
        guard let manifestData = try? await fetch(manifestURL),
              let manifest = DNSUpdatePlanner.parseManifest(manifestData),
              DNSUpdatePlanner.needsUpdate(localSHA: readAppliedSHA(), remote: manifest)
        else { return false }

        // 2. rules を取得し、sha256 検証 + JSON 配列検証（改竄/破損は破棄）
        guard let rulesData = try? await fetch(rulesURL),
              Self.sha256Hex(rulesData) == manifest.sha256,
              (try? JSONDecoder().decode([String].self, from: rulesData)) != nil
        else { return false }

        // 3. App Group へ atomic write + 適用 sha 記録
        do {
            try rulesData.write(to: appGroupRulesURL, options: [.atomic])
            try writeAppliedSHA(manifest.sha256)
            return true
        } catch {
            return false
        }
    }

    // MARK: - 適用 sha 記録

    private func readAppliedSHA() -> String? {
        guard let data = try? Data(contentsOf: appliedRecordURL),
              let record = try? JSONDecoder().decode([String: String].self, from: data)
        else { return nil }
        return record["sha256"]
    }

    private func writeAppliedSHA(_ sha: String) throws {
        let data = try JSONEncoder().encode(["sha256": sha])
        try data.write(to: appliedRecordURL, options: [.atomic])
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
