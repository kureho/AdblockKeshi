import Foundation

struct BlockerListResolver {
    let appGroupIdentifier: String
    let filterFilename: String
    let bundle: Bundle
    private let fileManager: FileManager

    init(
        appGroupIdentifier: String = "group.com.kureho.adblockkeshi.shared",
        filterFilename: String = "blockerList.json",
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) {
        self.appGroupIdentifier = appGroupIdentifier
        self.filterFilename = filterFilename
        self.bundle = bundle
        self.fileManager = fileManager
    }

    /// App Group コンテナ優先 → Bundle フォールバック。
    /// Plan B で runtime download が App Group に書き込んだ最新フィルタを優先採用するための構造。
    func resolve() -> URL? {
        if let url = appGroupURL(), fileManager.fileExists(atPath: url.path) {
            return url
        }
        return bundleURL()
    }

    func appGroupURL() -> URL? {
        fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(filterFilename)
    }

    func bundleURL() -> URL? {
        let basename = (filterFilename as NSString).deletingPathExtension
        let ext = (filterFilename as NSString).pathExtension
        return bundle.url(forResource: basename, withExtension: ext)
    }

    // MARK: - v2.0 state-aware resolution

    /// v2.0: state に応じて 4 種類のルール JSON を切替えるリゾルバ。
    /// App Group → Bundle → empty-rules.json の fallback chain で URL 解決。
    func resolve(for state: BlockerTogglesState) -> URL? {
        let filename = self.filename(for: state)
        return resolveStateFile(filename: filename)
    }

    /// state → filename マッピング（テスト容易性のため public）。
    func filename(for state: BlockerTogglesState) -> String {
        switch (state.adEnabled, state.securityEnabled) {
        case (true,  true):  return "merged-rules.json"
        case (true,  false): return "ad-rules.json"
        case (false, true):  return "security-rules.json"
        case (false, false): return "empty-rules.json"
        }
    }

    /// 任意 filename について App Group → bundle → empty-rules の chain で URL 解決。
    private func resolveStateFile(filename: String) -> URL? {
        if let container = fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let candidate = container.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        let basename = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        if let bundleURL = bundle.url(forResource: basename, withExtension: ext) {
            return bundleURL
        }
        // 最終 fallback: bundle 同梱の empty-rules.json（Extension クラッシュ回避）
        return bundle.url(forResource: "empty-rules", withExtension: "json")
    }
}
