import Foundation

/// 自己報告ファストレーンの保存層。
///
/// - `rules-self.json`   … 報告した本人の端末ルール（即時追記）
/// - `rules-global.json` … サーバ検証を通って配信されたグローバルルール（FilterDownloader が保存）
/// - `rules-reported.json` … 上2つを union した安全な自己学習集合。4→3 統合後は
///                           `CombinedRuleListCoordinator` が `safeMergedReportedRules()` 経由で
///                           読み、標準 ContentBlocker の combined-<state> に統合する。
///
/// 重複はルール内容で排除する。
struct SelfReportedRulesStore {
    static let selfFilename = "rules-self.json"
    static let globalFilename = "rules-global.json"
    static let mergedFilename = "rules-reported.json"

    let directory: URL
    private let fileManager: FileManager

    /// テスト用: 任意ディレクトリを直接指定。
    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// 本番用: App Group コンテナ直下を使う。コンテナが取れなければ nil。
    init?(appGroupIdentifier: String = "group.com.kureho.adblockkeshi.shared",
          fileManager: FileManager = .default) {
        guard let container = fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else { return nil }
        self.directory = container
        self.fileManager = fileManager
    }

    /// 自己報告ルールを追加し merged を再構築。新規追加されたら true（重複は false）。
    @discardableResult
    func appendSelfRule(_ rule: ContentBlockerRule) throws -> Bool {
        var selfRules = loadSelfRules()
        let key = rule.trigger.urlFilter
        guard !selfRules.contains(where: { $0.trigger.urlFilter == key }) else {
            return false
        }
        selfRules.append(rule)
        try write(selfRules, to: Self.selfFilename)
        try rebuildMerged()
        return true
    }

    /// self + global を union して merged を書く。
    /// 防御多層: 経路を問わず document ブロック(旧形式)は merged から除外する
    /// （CDN/global 経由で混入しても無効化）。dedup はルール内容で行う
    /// （cosmetic は url-filter `.*` を共有するため url-filter dedup では取りこぼす）。
    /// 戻り値: merged ファイルの中身が以前と変わったら true（呼び出し側の reload 判断用）。
    @discardableResult
    func rebuildMerged() throws -> Bool {
        let union = safeMergedReportedRules()
        let previous = loadMergedRules()
        try write(union, to: Self.mergedFilename)
        return union != previous
    }

    /// self ∪ global を「document ブロック除外 + structural dedup」した安全な自己学習ルール集合を返す。
    /// 並び順は **global → self**（self を末尾に置く）。予算超過時に `ReportedRuleBudget.selectReported`
    /// が末尾を優先保持するため、ユーザー自身の報告（self・ファストレーン）が global より優先して
    /// combined に載る。dedup は内容一致で行い、最初の出現（global 側）を残す。
    func safeMergedReportedRules() -> [ContentBlockerRule] {
        var seen = Set<ContentBlockerRule>()
        var union: [ContentBlockerRule] = []
        for rule in loadGlobalRules() + loadSelfRules() {
            guard !ReportedRuleSafety.isDocumentBlockingRisk(rule) else { continue }
            if seen.insert(rule).inserted {
                union.append(rule)
            }
        }
        return union
    }

    /// 既存端末治癒: 保存済み self ルールから document ブロック(旧形式)を除去し merged を作り直す。
    /// ネットワーク非依存・idempotent。self の除去 or merged 内容の変化が起きたら true
    /// （global 由来の危険ルールが merged から strip される場合も reload を促すため）。
    @discardableResult
    func sanitizeStoredSelfRules() throws -> Bool {
        let current = loadSelfRules()
        let safe = current.filter { !ReportedRuleSafety.isDocumentBlockingRisk($0) }
        let selfChanged = safe.count != current.count
        if selfChanged { try write(safe, to: Self.selfFilename) }
        let mergedChanged = try rebuildMerged()
        return selfChanged || mergedChanged
    }

    func loadSelfRules() -> [ContentBlockerRule] { load(Self.selfFilename) }
    func loadGlobalRules() -> [ContentBlockerRule] { load(Self.globalFilename) }
    func loadMergedRules() -> [ContentBlockerRule] { load(Self.mergedFilename) }

    // MARK: - IO

    private func load(_ filename: String) -> [ContentBlockerRule] {
        let url = directory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url),
              let rules = try? JSONDecoder().decode([ContentBlockerRule].self, from: data)
        else { return [] }
        return rules
    }

    private func write(_ rules: [ContentBlockerRule], to filename: String) throws {
        let data = try JSONEncoder().encode(rules)
        try data.write(to: directory.appendingPathComponent(filename), options: [.atomic])
    }
}
