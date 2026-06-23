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
        // 統合: App Group の `combined-<filename>`（popunder L1+L2 + 安全化 reported）を最優先。
        // 無ければ App Group の元ファイル（CDN 配信）→ bundle にフォールバック（fail-safe）。
        if let container = fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let combined = container.appendingPathComponent(
                CombinedRuleListBuilder.combinedFilename(forVariant: filterFilename))
            if fileManager.fileExists(atPath: combined.path) {
                return combined
            }
            let direct = container.appendingPathComponent(filterFilename)
            if fileManager.fileExists(atPath: direct.path) {
                return direct
            }
        }
        return bundleURL()
    }

    /// combined を考慮しない base 解決: App Group の `filterFilename`（CDN 配信）→ bundle。
    /// combined-<filename> の生成元（base）を取得するために使う（combined を見ると循環するため除外）。
    func resolveDirect() -> URL? {
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
    /// 統合(4→3): App Group の `combined-<variant>`（標準+安全化済み自己学習）を最優先し、
    /// 無ければ標準のみ（App Group `<variant>` → bundle → empty）にフォールバックする（fail-safe）。
    func resolve(for state: BlockerTogglesState) -> URL? {
        let variant = self.filename(for: state)
        if let container = fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let combined = container.appendingPathComponent(
                CombinedRuleListBuilder.combinedFilename(forVariant: variant))
            if fileManager.fileExists(atPath: combined.path) {
                return combined
            }
        }
        return resolveStateFile(filename: variant)
    }

    /// combined を考慮しない「標準 variant のみ」の解決（CombinedRuleListBuilder の入力源）。
    /// App Group `<variant>` → bundle `<variant>` → bundle empty。combined は見ない（循環回避）。
    func standardRulesURL(for state: BlockerTogglesState) -> URL? {
        resolveStateFile(filename: filename(for: state))
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
