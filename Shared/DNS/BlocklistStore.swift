import Foundation

/// tunnel が読む curated ブロックリストのロード層。
/// 優先順: App Group の dns-rules.json（self-fetch で更新される）→ bundle 同梱初期リスト → 空。
/// 空でも DNSEngine は fail-open で forward するので安全（ブロックが減るだけで通信は壊れない）。
/// App Group / bundle URL は DI 可能（StateStore の init(stateFileURL:) パターン踏襲・テスト可能）。
struct BlocklistStore {
    /// App Group container の dns-rules.json（無い/空なら bundle へフォールバック）。
    let appGroupFileURL: URL?
    /// bundle 同梱の初期 dns-rules.json（fresh install で App Group が空でも読める）。
    let bundleFileURL: URL?

    init(appGroupFileURL: URL?, bundleFileURL: URL?) {
        self.appGroupFileURL = appGroupFileURL
        self.bundleFileURL = bundleFileURL
    }

    /// 本番配線: App Group container + bundle 同梱リソース。
    static func shared(
        appGroupIdentifier: String = "group.com.kureho.adblockkeshi.shared",
        bundle: Bundle = .main
    ) -> BlocklistStore {
        let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        return BlocklistStore(
            appGroupFileURL: container?.appendingPathComponent("dns-rules.json"),
            bundleFileURL: bundle.url(forResource: "dns-rules", withExtension: "json"))
    }

    /// curated ドメインをロードする。
    func loadDomains() -> [String] {
        // 1. App Group（self-fetch で更新される最新）。非空のときだけ採用（空/不正は bundle を隠さない）。
        if let url = appGroupFileURL, let domains = Self.decode(url), !domains.isEmpty {
            return domains
        }
        // 2. bundle 同梱の初期リスト
        if let url = bundleFileURL, let domains = Self.decode(url) {
            return domains
        }
        // 3. 空（DNSEngine は fail-open で forward）
        return []
    }

    private static func decode(_ url: URL) -> [String]? {
        guard let data = try? Data(contentsOf: url),
              let domains = try? JSONDecoder().decode([String].self, from: data)
        else { return nil }
        return domains
    }
}
